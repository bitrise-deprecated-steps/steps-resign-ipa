require 'tmpdir'
require 'spaceship'
require 'fileutils'

class Resigner
	def resign(distribution_type, ipa_path, provisioning_profile, team_id=nil, app_id_prefix=nil)
		certificates, certificate_team_id = list_valid_certificate_names(distribution_type, team_id)
		puts "certificates:"
		puts certificates.inspect
		puts "certificate_team_id:"
		puts certificate_team_id.inspect
		raise 'team id conflicted' if !team_id.nil? && !certificate_team_id.eql?(team_id)
		team_id = certificate_team_id
		app_id_prefix = team_id if app_id_prefix.nil?

		if certificates.count > 1
			puts "⚠️  Warning, multiple matching certs found, using first match from:"
			puts certificates.inspect
		end

		selected_certificate_name = certificates[0]

		expended_ipa_path = File.expand_path(ipa_path)

		puts "Resigning ipa `#{ipa_path}` with team id `#{team_id}`"

		new_ipa_path = "#{File.dirname(expended_ipa_path)}/#{File.basename(expended_ipa_path, '.ipa')}-#{distribution_type}-resigned.ipa"
		FileUtils.copy_file(expended_ipa_path, new_ipa_path)
		provisioning_profile_path = File.expand_path("~/Library/MobileDevice/Provisioning Profiles/#{provisioning_profile}.mobileprovision")
		system("fastlane sigh resign '#{new_ipa_path}' --signing_identity '#{selected_certificate_name}' --provisioning_profile '#{provisioning_profile_path}'")
		export_ipa(new_ipa_path)
	end

	private

	def get_distribution_type_name(distribution_type)
        #TODO this needs to be updated to handle Apple Developer certs if we switch to those
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

	def export_ipa(new_ipa_path)
		# `zip --symlinks --verbose --recurse-paths "#{new_ipa_path}" *`
		puts "\e[32mResigned ipa is available at: #{new_ipa_path}\e[0m"

		puts
		puts "The resigned IPA path is now available in the Environment Variable: $BITRISE_RESIGNED_IPA_PATH'"
		`envman add --key BITRISE_RESIGNED_IPA_PATH --value "#{new_ipa_path}"`
	end
end
