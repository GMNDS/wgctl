require "base64"
require "random/secure"

module Wgctl
  module WireGuard
    class Keys
      # Generates a WireGuard private key using `wg genkey` or fallback
      def self.generate_private_key : String
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run("wg", ["genkey"], output: stdout, error: stderr)
        if status.success?
          return stdout.to_s.strip
        end

        # Fallback: 32 random bytes clamped for X25519
        bytes = Random::Secure.random_bytes(32)
        bytes[0] &= 248_u8
        bytes[31] &= 127_u8
        bytes[31] |= 64_u8
        Base64.strict_encode(bytes)
      rescue
        bytes = Random::Secure.random_bytes(32)
        bytes[0] &= 248_u8
        bytes[31] &= 127_u8
        bytes[31] |= 64_u8
        Base64.strict_encode(bytes)
      end

      # Computes public key from private key using `wg pubkey`
      def self.public_key(private_key : String) : String
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        process = Process.new(
          "wg",
          ["pubkey"],
          input: Process::Redirect::Pipe,
          output: stdout,
          error: stderr
        )
        process.input.puts(private_key.strip)
        process.input.close
        status = process.wait

        if status.success?
          stdout.to_s.strip
        else
          raise "Failed to compute public key using 'wg pubkey': #{stderr.to_s}"
        end
      end

      # Generates a WireGuard pre-shared key
      def self.generate_preshared_key : String
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run("wg", ["genpsk"], output: stdout, error: stderr)
        if status.success?
          return stdout.to_s.strip
        end

        Base64.strict_encode(Random::Secure.random_bytes(32))
      rescue
        Base64.strict_encode(Random::Secure.random_bytes(32))
      end
    end
  end
end
