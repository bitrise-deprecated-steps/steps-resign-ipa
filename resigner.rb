require 'tmpdir'
require 'spaceship'
require 'fileutils'

class Resigner
  def resign(distribution_type, ipa_path, team_id=nil, app_id_prefix=nil)
    certificates, certificate_team_id = list_valid_certificate_names(distribution_type, team_id)
    raise 'team id conflicted' if !team_id.nil? && !certificate_team_id.eql?(team_id)
    team_id = certificate_team_id
    app_id_prefix = team_id if app_id_prefix.nil?

    expended_ipa_path = File.expand_path(ipa_path)

    puts "Resigning ipa `#{ipa_path}` with team id `#{team_id}`"
    tmpdir = Dir.mktmpdir
    Dir.chdir(tmpdir) do
      unzip(expended_ipa_path)
      unsign

      embedded_mobileprovisions = gather_embedded_provisioning_profiles()
      bundle_identifiers = embedded_mobileprovisions.collect { |embedded_mobileprovision| embedded_mobileprovision[:bundle_identifier] }

      selected_certificate_name, provisioning_profiles_for_bundle_ids = gather_certificate_and_provisioning_profiles(distribution_type, team_id, app_id_prefix, certificates, bundle_identifiers)
      raise 'no valid provisioning profiles found for installed certificates' unless selected_certificate_name

      update_embedded_mobileprovisions(embedded_mobileprovisions, provisioning_profiles_for_bundle_ids)
      add_swift_support_library
      resign_ipa(selected_certificate_name)

      resign_result = `codesign -v Payload/*.app 2>&1`
      raise resign_result unless resign_result.to_s.eql?('')

      zip(File.join(File.dirname(ipa_path), "#{File.basename(ipa_path, '.ipa')}-#{distribution_type}-resigned.ipa"))
    end
    FileUtils.rm_rf(tmpdir)
  end

  private

  def unzip(ipa_path)
    unzip_results = `/usr/bin/unzip -q "#{ipa_path}"`
    raise "\e[31mError: #{unzip_results}\e[0m" unless $?.exitstatus.eql?(0)
  end

  def unsign
    Dir['Payload/**/_CodeSignature'].each { |directory| FileUtils.rm_rf(directory) }
  end

  def get_distribution_type_name(distribution_type)
    case distribution_type.downcase
    when "appstore", "inhouse"
      return 'iPhone Distribution:'
    when "development"
      return 'iPhone Developer:'
    else
      raise 'invalid distribution type'
    end
  end

  def list_valid_certificate_names(distribution_type, team_id = nil)
    distribution_type_name = get_distribution_type_name(distribution_type)

    certificates = []
    teams = []
    `security find-identity -v -p codesigning`.split("\n").each do |line|
      if match = /(#{distribution_type_name}[^"]*)/i.match(line)
        identity_name = match.captures.first
        subject = `security find-certificate -c '#{identity_name}' -p | openssl x509 -text | grep 'Subject:'`

        if match = /OU=(\w*)/.match(subject)
          team = match.captures.first
          next if !team_id.nil? && !team.eql?(team_id)

          teams << team unless teams.include?(team)
          certificates << identity_name
        end
      end
    end

    raise 'no valid certificates found' if certificates.empty?
    raise 'multiple teams found. Please specify a `team id`' if teams.count > 1
    return certificates, teams.first
  end

  def gather_embedded_provisioning_profiles(path_to_payload='.')
    embedded_mobileprovisions = []
    Dir[File.join(path_to_payload, 'Payload/**/embedded.mobileprovision')].each do |mobileprovision|
      provisioning_profile = Plist::parse_xml(`security cms -D -i "#{mobileprovision}"`)

      embedded_mobileprovisions << {
        bundle_identifier: `/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "#{[File.dirname(mobileprovision), 'Info.plist'].join(File::SEPARATOR)}"`.strip,
        team_id: provisioning_profile['Entitlements']['com.apple.developer.team-identifier'],
        path: mobileprovision,
      }
    end
    return embedded_mobileprovisions
  end

  def gather_certificate_and_provisioning_profiles(distribution_type, team_id, app_id_prefix, certificates, bundle_identifiers)
    plists = []
    valid_certs = {}
    Dir[File.expand_path("~/Library/MobileDevice/Provisioning Profiles/*.mobileprovision")].each do |provisioning_profile|
      plist = Plist::parse_xml(`security cms -D -i "#{provisioning_profile}"`)
      if plist['Entitlements']['com.apple.developer.team-identifier'].eql?(team_id)
        bundle_identifiers.each do |bundle_identifier|
          next unless File.fnmatch(plist['Entitlements']['application-identifier'], "#{app_id_prefix}.#{bundle_identifier}")

          # Check if we have a valid certificate for the provisioning profile
          plist['DeveloperCertificates'].each do |developer_certificate|
            cert = OpenSSL::X509::Certificate.new(developer_certificate.string)

            certificates.select { |certificate| !/#{Regexp.quote("/CN=#{certificate}/OU=#{team_id}")}/i.match(cert.subject.to_s).nil? }.each do |certificate|
              valid_certs[certificate] ||= {}

              case distribution_type.downcase
              when "appstore"
                if !plist['Entitlements']['get-task-allow'].eql?(true) && plist['ProvisionedDevices'].nil? && !plist['Entitlements']['application-identifier'].end_with?('*')
                  (valid_certs[certificate][bundle_identifier] ||= []) << provisioning_profile
                end
              when "inhouse"
                if !plist['Entitlements']['get-task-allow'].eql?(true) && !plist['ProvisionedDevices'].nil?
                  (valid_certs[certificate][bundle_identifier] ||= []) << provisioning_profile
                end
              when "development"
                if plist['Entitlements']['get-task-allow'].eql?(true)
                  (valid_certs[certificate][bundle_identifier] ||= []) << provisioning_profile
                end
              else
                raise 'invalid distribution type'
              end
            end
          end
        end
      end
    end
    selected_certificate_name, bundle_ids = valid_certs.find{ |certificate, value| value.keys.count.eql?(bundle_identifiers.count) }
  end

  def update_embedded_mobileprovisions(embedded_mobileprovisions, provisioning_profiles_for_bundle_ids)
    embedded_mobileprovisions.each do |mobileprovision|
      provisioning_profile_path = provisioning_profiles_for_bundle_ids[mobileprovision[:bundle_identifier]].first
      embedded_mobileprovision_path = mobileprovision[:path]

      FileUtils.cp provisioning_profile_path, embedded_mobileprovision_path
    end
  end

  def add_swift_support_library()
    unless Dir["Payload/*.app/Frameworks/libswift*"].empty?
      developer_directory=`xcode-select --print-path`.strip!
      raise 'No developer directory found' unless developer_directory

      swift_support_directory = 'SwiftSupport/iphoneos'
      FileUtils::mkdir_p swift_support_directory

      Dir["Payload/*.app/Frameworks/libswift*"].each do |dylib_path|
        dirname = File.dirname(dylib_path)
        dylib = File.basename(dylib_path)
        FileUtils.copy(File.join(developer_directory, 'Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos', dylib), File.join(swift_support_directory, dylib))
        FileUtils.copy(File.join(developer_directory, 'Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos', dylib), File.join(dirname, dylib))
      end
    end
  end

  def resign_ipa(code_signing_identity)
    pathes_to_sign = Dir['Payload/**/*.{app,appex,dylib,framework}']
    pathes_to_sign.sort! { |path1, path2| path2.split(File::SEPARATOR).count <=> path1.split(File::SEPARATOR).count }

    pathes_to_sign.each do |path_to_sign|
      profile_path = 'profile.plist'
      entitlements_path = 'entitlements.plist'

      embedded_profile_path = File.join(path_to_sign, 'embedded.mobileprovision')
      if File.exist?(embedded_profile_path)
        plist = Plist::parse_xml(`security cms -D -i "#{embedded_profile_path}" > #{profile_path}`)
        `/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' #{profile_path} > #{entitlements_path}`
        `/usr/bin/codesign -f -s "#{code_signing_identity}" --entitlements #{entitlements_path} "#{path_to_sign}" 2>/dev/null`
      else
        `/usr/bin/codesign -f -s "#{code_signing_identity}" "#{path_to_sign}" 2>/dev/null`
      end

      File.delete(entitlements_path) if File.exist?(entitlements_path)
      File.delete(profile_path) if File.exist?(profile_path)
    end
  end

  def zip(new_ipa_path)
    `zip -qr "#{new_ipa_path}" *`
    puts "\e[32mResigned ipa is available at: #{new_ipa_path}\e[0m"

    puts
    puts "The resigned IPA path is now available in the Environment Variable: $BITRISE_RESIGNED_IPA_PATH'"
    `envman add --key BITRISE_RESIGNED_IPA_PATH --value "#{new_ipa_path}"`
  end
end
