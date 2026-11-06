# Run a Sonic Pi script with no GUI, audible. Usage: sp-run.rb script.rb [seconds]
require_relative File.expand_path("~/Applications/sonic-pi/usr/share/sonic-pi/app/server/ruby/bin/headless_boot")
script   = File.expand_path(ARGV[0].to_s)
duration = (ARGV[1] || "20").to_f
abort "File not found: #{script}" unless File.exist?(script)
boot = SonicPi::HeadlessBoot.new
boot.boot! { |osc| }
boot.eval_client.send("/mixer-output-volume", boot.token, (ENV["SP_VOL"] || "1.0").to_f, 0)
boot.say "READY - running #{script} for #{duration}s"
boot.run("run_file #{script.inspect}")
sleep duration
boot.say "done - stopping"
boot.stop_all
sleep 0.5
exit 0
