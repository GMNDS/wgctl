require "./terminal"
require "../cli/context"
require "../models/interface"
require "../models/peer"
require "../models/metadata"
require "../config/writer"
require "../config/ip_allocator"
require "../config/validator"
require "../wireguard/keys"
require "../wireguard/runner"

module Wgctl
  module TUI
    enum Mode
      Dashboard
      PeerDetail
      PeerEdit
      PeerAdd
      QRCode
      ClientConfig
      ConfirmDelete
    end

    class App
      property context : CLI::Context
      property iface : Models::Interface
      property selected_index : Int32 = 0
      property mode : Mode = Mode::Dashboard
      property message : String?
      property error_message : String?
      property active_peer : Models::Peer?
      property qr_content : String? = nil
      property client_conf_content : String? = nil

      # Form fields for Edit / Add
      property form_name : String = ""
      property form_desc : String = ""
      property form_device : String = ""
      property form_ip : String = ""
      property form_focus : Int32 = 0 # 0=name, 1=desc, 2=device, 3=ip

      def initialize(@context : CLI::Context, @iface : Models::Interface)
      end

      def reload_interface
        @iface = @context.load_interface(@iface.name)
        if @selected_index >= @iface.peers.size
          @selected_index = Math.max(0, @iface.peers.size - 1)
        end
      end

      def current_peer : Models::Peer?
        return nil if @iface.peers.empty?
        @iface.peers[@selected_index]?
      end

      def run
        Terminal.enter_alternate_screen
        begin
          STDIN.raw do |raw_io|
            loop do
              render
              key_event = Terminal.read_key(raw_io)
              break if handle_input(raw_io, key_event)
            end
          end
        ensure
          Terminal.exit_alternate_screen
        end
      end

      def render
        Terminal.clear_screen

        case @mode
        when Mode::Dashboard
          render_dashboard
        when Mode::PeerDetail
          render_peer_detail
        when Mode::PeerEdit
          render_peer_edit
        when Mode::PeerAdd
          render_peer_add
        when Mode::QRCode
          render_qr_code
        when Mode::ClientConfig
          render_client_config
        when Mode::ConfirmDelete
          render_confirm_delete
        end
      end

      private def render_dashboard
        io = IO::Memory.new

        # Title and Header
        io.puts "\e[1;36m=== wgctl - Gerenciador WireGuard Interativo ===\e[0m"
        online_count = @iface.peers.count(&.online?)
        port_str = @iface.effective_listen_port.try(&.to_s) || "N/A"
        io.puts "Interface: \e[1m#{@iface.name}\e[0m | Endereço: \e[1m#{@iface.effective_address}\e[0m | Porta: \e[1m#{port_str}\e[0m | Peers: \e[1m#{@iface.peers.size}\e[0m (\e[32m#{online_count} online\e[0m)"

        # Alert if peers lack metadata
        unnamed_count = @iface.peers.count { |p| !p.has_name? }
        if unnamed_count > 0
          io.puts "\e[1;33m⚠️  #{unnamed_count} peer(s) sem metadados! Selecione e pressione 'e' para nomear.\e[0m"
        else
          io.puts ""
        end

        # Status or Error banner
        if msg = @message
          io.puts "\e[1;32m✓ #{msg}\e[0m"
          @message = nil
        elsif err = @error_message
          io.puts "\e[1;31m✗ #{err}\e[0m"
          @error_message = nil
        else
          io.puts ""
        end

        # Table Header
        io.puts sprintf("  %-10s %-18s %-16s %-20s %-12s %-18s", "STATUS", "NOME", "IP", "ENDPOINT", "HANDSHAKE", "TRAFEGO (RX/TX)")
        io.puts "  " + ("-" * 98)

        if @iface.peers.empty?
          io.puts "  Nenhum peer configurado. Pressione 'a' para adicionar um peer."
        else
          @iface.peers.each_with_index do |peer, idx|
            selected = (idx == @selected_index)
            prefix = selected ? "\e[1;36m▶\e[0m " : "  "

            status_badge = peer.online? ? "\e[32m● ONLINE \e[0m" : "\e[90m○ OFFLINE\e[0m"
            name_display = peer.has_name? ? peer.name : "\e[1;33m[SEM NOME]\e[0m"
            if name_display.size > 18
              name_display = "#{name_display[0...15]}..."
            end

            ep_display = peer.effective_endpoint
            if ep_display.size > 20
              ep_display = "#{ep_display[0...17]}..."
            end

            traffic = "#{peer.effective_rx} / #{peer.effective_tx}"

            line = sprintf("%-10s %-18s %-16s %-20s %-12s %-18s",
              status_badge,
              name_display,
              peer.primary_ip,
              ep_display,
              peer.effective_handshake,
              traffic
            )

            if selected
              io.puts "#{prefix}\e[7m#{line}\e[0m"
            else
              io.puts "#{prefix}#{line}"
            end
          end
        end

        # Detail box of selected peer
        io.puts ""
        if peer = current_peer
          io.puts "  \e[1mDetalhes do Peer Selecionado:\e[0m"
          desc = peer.description || "(nenhuma)"
          dev = peer.device || "(não especificado)"
          io.puts "  Chave Pública: \e[36m#{peer.public_key}\e[0m"
          io.puts "  Descrição:     #{desc} | Dispositivo: #{dev}"
        end

        # Footer Shortcuts
        io.puts "\n" + ("=" * 100)
        io.puts "\e[1m[↑/↓]\e[0m Navegar | \e[1m[e]\e[0m Editar/Nomear | \e[1m[a]\e[0m Adicionar | \e[1m[d]\e[0m Excluir | \e[1m[q]\e[0m QR Code | \e[1m[c]\e[0m Config | \e[1m[m]\e[0m Migrar Nyr | \e[1m[r]\e[0m Recarregar | \e[1m[Esc]\e[0m Sair"

        print io.to_s
        STDOUT.flush
      end

      private def render_peer_detail
        io = IO::Memory.new
        peer = current_peer
        return back_to_dashboard unless peer

        io.puts "\e[1;36m=== Detalhes do Peer: #{peer.name} ===\e[0m\n"
        io.puts sprintf("%-18s%s", "Nome:", peer.name)
        io.puts sprintf("%-18s%s", "Descrição:", peer.description || "(nenhuma)")
        io.puts sprintf("%-18s%s", "Dispositivo:", peer.device || "(não especificado)")
        io.puts sprintf("%-18s%s", "Chave Pública:", peer.public_key)
        io.puts sprintf("%-18s%s", "Endereços IP:", peer.clean_ips)
        io.puts sprintf("%-18s%s", "Endpoint:", peer.effective_endpoint)
        io.puts sprintf("%-18s%s", "Último Handshake:", peer.effective_handshake)
        io.puts sprintf("%-18s%s", "Recebido (RX):", peer.effective_rx)
        io.puts sprintf("%-18s%s", "Enviado (TX):", peer.effective_tx)

        io.puts "\n" + ("-" * 60)
        io.puts "\e[1m[e]\e[0m Editar Metadados | \e[1m[q]\e[0m QR Code | \e[1m[c]\e[0m Ver Config | \e[1m[Esc]\e[0m Voltar"

        print io.to_s
        STDOUT.flush
      end

      private def render_peer_edit
        io = IO::Memory.new
        peer = current_peer
        return back_to_dashboard unless peer

        io.puts "\e[1;36m=== Editar / Nomear Peer ===\e[0m"
        io.puts "Chave Pública: \e[33m#{peer.public_key}\e[0m"
        io.puts "Preencha os metadados abaixo e pressione Enter para confirmar.\n"

        fields = [
          {"Nome:", @form_name, 0},
          {"Descrição:", @form_desc, 1},
          {"Dispositivo:", @form_device, 2},
          {"IP (/32 ou auto):", @form_ip, 3}
        ]

        fields.each do |label, value, idx|
          focused = (@form_focus == idx)
          prefix = focused ? "\e[1;32m▶ " : "  "
          cursor_hint = focused ? " \e[4m#{value}\e[0m" : " #{value}"
          io.puts sprintf("%s%-18s%s", prefix, label, cursor_hint)
        end

        io.puts "\n" + ("-" * 60)
        io.puts "\e[1m[Tab / ↑ / ↓]\e[0m Trocar Campo | \e[1m[Enter]\e[0m Salvar | \e[1m[Esc]\e[0m Cancelar"

        print io.to_s
        STDOUT.flush
      end

      private def render_peer_add
        io = IO::Memory.new
        io.puts "\e[1;36m=== Adicionar Novo Peer ===\e[0m"
        io.puts "Preencha os dados do novo cliente WireGuard.\n"

        fields = [
          {"Nome:", @form_name, 0},
          {"Descrição:", @form_desc, 1},
          {"Dispositivo:", @form_device, 2},
          {"IP (auto ou manual):", @form_ip, 3}
        ]

        fields.each do |label, value, idx|
          focused = (@form_focus == idx)
          prefix = focused ? "\e[1;32m▶ " : "  "
          cursor_hint = focused ? " \e[4m#{value}\e[0m" : " #{value}"
          io.puts sprintf("%s%-22s%s", prefix, label, cursor_hint)
        end

        io.puts "\n" + ("-" * 60)
        io.puts "\e[1m[Tab / ↑ / ↓]\e[0m Trocar Campo | \e[1m[Enter]\e[0m Criar Peer | \e[1m[Esc]\e[0m Cancelar"

        print io.to_s
        STDOUT.flush
      end

      private def render_qr_code
        io = IO::Memory.new
        peer = current_peer
        peer_name = peer ? peer.name : "cliente"

        io.puts "\e[1;36m=== QR Code de Configuração: #{peer_name} ===\e[0m"
        io.puts "Escaneie o QR Code abaixo com o aplicativo WireGuard (Android / iOS):\n"
        if qr = @qr_content
          io.puts qr
        else
          io.puts "QR Code não disponível. Verifique se o pacote 'qrencode' está instalado."
        end
        io.puts "\n\e[1mPressione qualquer tecla ou [Esc] para voltar...\e[0m"

        print io.to_s
        STDOUT.flush
      end

      private def render_client_config
        io = IO::Memory.new
        peer = current_peer
        peer_name = peer ? peer.name : "cliente"

        io.puts "\e[1;36m=== Arquivo de Configuração (.conf): #{peer_name} ===\e[0m\n"
        if conf = @client_conf_content
          io.puts conf
        else
          io.puts "Configuração não disponível."
        end
        io.puts "\n\e[1mPressione qualquer tecla ou [Esc] para voltar...\e[0m"

        print io.to_s
        STDOUT.flush
      end

      private def render_confirm_delete
        io = IO::Memory.new
        peer = current_peer
        return back_to_dashboard unless peer

        io.puts "\e[1;31m=== Confirmar Exclusão de Peer ===\e[0m\n"
        io.puts "Tem certeza que deseja remover o peer abaixo da interface \e[1m#{@iface.name}\e[0m?"
        io.puts "  Nome:         \e[1m#{peer.name}\e[0m"
        io.puts "  Chave Pública: #{peer.public_key}"
        io.puts "  IPs:           #{peer.clean_ips}\n"
        io.puts "\e[1;31m[s / y]\e[0m Confirmar exclusão | \e[1m[n / Esc]\e[0m Cancelar"

        print io.to_s
        STDOUT.flush
      end

      def handle_input(raw_io : IO, event : KeyEvent) : Bool
        case @mode
        when Mode::Dashboard
          handle_dashboard_input(event)
        when Mode::PeerDetail
          case event.key
          when Key::Escape
            back_to_dashboard
          when Key::Char
            case event.char
            when 'e' then open_edit_form
            when 'q' then show_qr_code
            when 'c' then show_client_config
            else back_to_dashboard
            end
          else
            back_to_dashboard
          end
          false
        when Mode::PeerEdit
          handle_form_input(event, is_add: false)
        when Mode::PeerAdd
          handle_form_input(event, is_add: true)
        when Mode::QRCode, Mode::ClientConfig
          back_to_dashboard
          false
        when Mode::ConfirmDelete
          handle_delete_confirm(event)
        else
          false
        end
      end

      private def handle_dashboard_input(event : KeyEvent) : Bool
        case event.key
        when Key::Up
          @selected_index = Math.max(0, @selected_index - 1)
        when Key::Down
          @selected_index = Math.min(@iface.peers.size - 1, @selected_index + 1)
        when Key::Enter
          @mode = Mode::PeerDetail if current_peer
        when Key::Escape
          return true # Quit app
        when Key::Char
          case event.char
          when 'q'
            show_qr_code
          when 'e'
            open_edit_form
          when 'a'
            open_add_form
          when 'd'
            @mode = Mode::ConfirmDelete if current_peer
          when 'c'
            show_client_config
          when 'm'
            migrate_legacy_nyr
          when 'r'
            reload_interface
            @message = "Dados da interface atualizados."
          when 'x', 'Q'
            return true
          end
        end
        false
      end

      private def open_edit_form
        peer = current_peer
        return unless peer

        @form_name = peer.has_name? ? peer.name : ""
        @form_desc = peer.description || ""
        @form_device = peer.device || ""
        @form_ip = peer.primary_ip
        @form_focus = 0
        @mode = Mode::PeerEdit
      end

      private def open_add_form
        @form_name = ""
        @form_desc = ""
        @form_device = "mobile"
        @form_ip = "auto"
        @form_focus = 0
        @mode = Mode::PeerAdd
      end

      private def show_qr_code
        peer = current_peer
        return unless peer

        conf_str = generate_client_conf(peer)
        begin
          @qr_content = WireGuard::Runner.generate_qr_terminal(conf_str)
        rescue ex
          @qr_content = "Erro ao gerar QR Code: #{ex.message}"
        end
        @mode = Mode::QRCode
      end

      private def show_client_config
        peer = current_peer
        return unless peer

        @client_conf_content = generate_client_conf(peer)
        @mode = Mode::ClientConfig
      end

      private def migrate_legacy_nyr
        migrated = 0
        @iface.peers.each do |peer|
          peer.raw_comments.reject! do |c|
            s = c.strip
            s =~ /^#\s*BEGIN_PEER\s+/ || s =~ /^#\s*END_PEER\s+/
          end
          migrated += 1 if peer.has_name?
        end

        config_path = @iface.config_path
        if config_path
          Config::Writer.save_atomically(@iface, config_path, create_backup: true)
          reload_interface
          @message = "#{migrated} peer(s) migrado(s) para metadados # wgctl:* com sucesso!"
        end
      end

      private def handle_form_input(event : KeyEvent, is_add : Bool) : Bool
        case event.key
        when Key::Escape
          back_to_dashboard
        when Key::Up
          @form_focus = (@form_focus - 1) % 4
        when Key::Down
          @form_focus = (@form_focus + 1) % 4
        when Key::Backspace
          case @form_focus
          when 0 then @form_name = @form_name[0...-1] unless @form_name.empty?
          when 1 then @form_desc = @form_desc[0...-1] unless @form_desc.empty?
          when 2 then @form_device = @form_device[0...-1] unless @form_device.empty?
          when 3 then @form_ip = @form_ip[0...-1] unless @form_ip.empty?
          end
        when Key::Enter
          if is_add
            submit_add_peer
          else
            submit_edit_peer
          end
        when Key::Char
          if c = event.char
            case @form_focus
            when 0 then @form_name += c
            when 1 then @form_desc += c
            when 2 then @form_device += c
            when 3 then @form_ip += c
            end
          end
        end
        false
      end

      private def submit_edit_peer
        peer = current_peer
        return back_to_dashboard unless peer

        peer.metadata.name = @form_name.strip unless @form_name.strip.empty?
        peer.metadata.description = @form_desc.strip unless @form_desc.strip.empty?
        peer.metadata.device = @form_device.strip unless @form_device.strip.empty?

        ip_input = @form_ip.strip
        if !ip_input.empty? && ip_input != peer.primary_ip
          new_ip = ip_input == "auto" ? Config::IPAllocator.allocate_next(@iface) : (ip_input.includes?("/") ? ip_input : "#{ip_input}/32")
          peer.allowed_ips = [new_ip]
        end

        config_path = @iface.config_path
        if config_path
          Config::Writer.save_atomically(@iface, config_path, create_backup: true)
          if @iface.active
            WireGuard::Runner.apply_syncconf(@iface.name, config_path)
          end
          reload_interface
          @message = "Peer '#{peer.name}' atualizado com sucesso."
        end

        back_to_dashboard
      rescue ex
        @error_message = "Erro ao salvar: #{ex.message}"
        back_to_dashboard
      end

      private def submit_add_peer
        name = @form_name.strip
        if name.empty?
          @error_message = "O nome do peer não pode ficar vazio."
          return back_to_dashboard
        end

        ip_choice = @form_ip.strip
        allocated_ip = (ip_choice.empty? || ip_choice == "auto") ? Config::IPAllocator.allocate_next(@iface) : (ip_choice.includes?("/") ? ip_choice : "#{ip_choice}/32")

        client_priv = WireGuard::Keys.generate_private_key
        client_pub = WireGuard::Keys.public_key(client_priv)

        meta = Models::Metadata.new(
          name: name,
          description: @form_desc.strip.empty? ? nil : @form_desc.strip,
          device: @form_device.strip.empty? ? "mobile" : @form_device.strip,
          client_private_key: client_priv
        )

        new_peer = Models::Peer.new(
          public_key: client_pub,
          allowed_ips: [allocated_ip],
          metadata: meta,
          persistent_keepalive: 25
        )

        @iface.peers << new_peer

        config_path = @iface.config_path
        if config_path
          Config::Writer.save_atomically(@iface, config_path, create_backup: true)
          if @iface.active
            WireGuard::Runner.apply_syncconf(@iface.name, config_path)
          end
          reload_interface
          @selected_index = @iface.peers.size - 1
          @message = "Peer '#{name}' criado com sucesso (#{allocated_ip})."
        end

        back_to_dashboard
      rescue ex
        @error_message = "Erro ao criar peer: #{ex.message}"
        back_to_dashboard
      end

      private def handle_delete_confirm(event : KeyEvent) : Bool
        case event.key
        when Key::Escape
          back_to_dashboard
        when Key::Char
          if event.char == 's' || event.char == 'y' || event.char == 'S' || event.char == 'Y'
            delete_current_peer
          else
            back_to_dashboard
          end
        else
          back_to_dashboard
        end
        false
      end

      private def delete_current_peer
        peer = current_peer
        return back_to_dashboard unless peer

        peer_name = peer.name
        @iface.peers.reject! { |p| p.public_key == peer.public_key }

        config_path = @iface.config_path
        if config_path
          Config::Writer.save_atomically(@iface, config_path, create_backup: true)
          if @iface.active
            WireGuard::Runner.apply_syncconf(@iface.name, config_path)
          end
          reload_interface
          @message = "Peer '#{peer_name}' removido com sucesso."
        end

        back_to_dashboard
      rescue ex
        @error_message = "Erro ao remover peer: #{ex.message}"
        back_to_dashboard
      end

      private def back_to_dashboard
        @mode = Mode::Dashboard
      end

      private def generate_client_conf(peer : Models::Peer) : String
        client_priv = peer.metadata.client_private_key || "<CLIENT_PRIVATE_KEY>"
        server_pub = @iface.runtime_public_key
        if (server_pub.nil? || server_pub.empty?) && @iface.private_key
          server_pub = WireGuard::Keys.public_key(@iface.private_key.not_nil!) rescue "<SERVER_PUBLIC_KEY>"
        end
        server_pub ||= "<SERVER_PUBLIC_KEY>"

        endpoint = @iface.raw_properties["Endpoint"]?.try(&.first?) || "#{System.hostname}:#{@iface.effective_listen_port || 51820}"

        io = IO::Memory.new
        io.puts "[Interface]"
        io.puts "PrivateKey = #{client_priv}"
        io.puts "Address = #{peer.clean_ips}"
        if dns = @iface.raw_properties["DNS"]?.try(&.join(", "))
          io.puts "DNS = #{dns}"
        end
        io.puts ""
        io.puts "[Peer]"
        io.puts "PublicKey = #{server_pub}"
        io.puts "Endpoint = #{endpoint}"
        io.puts "AllowedIPs = 0.0.0.0/0, ::/0"
        io.puts "PersistentKeepalive = 25"
        io.to_s
      end
    end
  end
end
