require "#{__dir__}/resigner"

begin
	distribution_type = ENV['distribution_type']
	ipa_path = ENV['ipa_path']
	team_id = ENV['itunes_connect_team_id']
	app_id_prefix = ENV['app_id_prefix']

	puts 'Configs:'
	puts "  * ipa_path: #{ipa_path}"
	puts "  * distribution_type: #{distribution_type}"
	puts "  * team_id: #{team_id}"
	puts "  * app_id_prefix: #{app_id_prefix}"
	puts

	raise 'distribution_type is not set' unless distribution_type
	raise 'invalid distribution type' unless %w(appstore inhouse development).include?(distribution_type.downcase)

	raise 'ipa_path is not set' unless ipa_path
	raise 'File not found at ipa_path' unless File.exist?(ipa_path)

	team_id = nil if ENV['itunes_connect_team_id'].to_s.eql?('')

	app_id_prefix = nil if ENV['app_id_prefix'].to_s.eql?('')

	resigner = Resigner.new
	resigner.resign(distribution_type, ipa_path, team_id, app_id_prefix)
rescue => ex
	puts "\e[31mError: #{ex}\e[0"
	puts "\e[31mFailed to resign ipa\e[0m"
	puts ex.backtrace
	exit 1
end
