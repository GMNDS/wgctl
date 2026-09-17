require "../cli/context"
require "../models/interface"
require "../models/peer"
require "./status_command"
require "./peer_add_command"
require "./peer_edit_command"
require "./peer_remove_command"
require "./client_command"
require "./check_command"
require "./migrate_command"
require "./apply_command"
require "./init_command"

module Wgctl
  module Commands
    class MenuCommand
      def self.run(context : CLI::Context, args : Array(String))
        new(context, args).start
      end

      property context : CLI::Context
      property selected_iface_name : String?

      def initialize(@context : CLI::Context, args : Array(String))
        @selected_iface_name = @context.interface || args.first?
      end

      def start
        loop do
          iface = resolve_interface
          unless iface
            puts "Nenhuma interface WireGuard encontrada."
            print "Deseja inicializar uma nova interface agora com 'wgctl init'? (S/n): "
            resp = (gets || "").strip.downcase
            if resp.empty? || resp == "s" || resp == "y" || resp == "sim"
              InitCommand.run(@context, [] of String)
              next
            else
              puts "Encerrando wgctl."
              return
            end
          end

          render_menu(iface)
          print "Escolha uma opção [0-9]: "
          choice = (gets || "").strip

          case choice
          when "1"
            handle_status(iface)
          when "2"
            handle_add_peer(iface)
          when "3"
            handle_edit_peer(iface)
          when "4"
            handle_client_qr(iface)
          when "5"
            handle_remove_peer(iface)
          when "6"
            handle_check(iface)
          when "7"
            handle_migrate(iface)
          when "8"
            handle_apply(iface)
          when "9"
            InitCommand.run(@context, [] of String)
            wait_enter
          when "0", "q", "exit", "sair"
            puts "\nAté logo!"
            break
          else
            puts "\nOpção inválida. Pressione Enter para tentar novamente."
            wait_enter
          end
        end
      end

      private def resolve_interface : Models::Interface?
        begin
          if name = @selected_iface_name
            return @context.load_interface(name)
          end

          # Discover interfaces
          discovered = @context.discover_interfaces
          if discovered.empty?
            # Try default wg0 if config file exists
            default_path = @context.config_file || "/etc/wireguard/wg0.conf"
            if File.exists?(default_path)
              return @context.load_interface("wg0")
            end
            return nil
          elsif discovered.size == 1
            @selected_iface_name = discovered.first
            return @context.load_interface(@selected_iface_name.not_nil!)
          else
            puts "\nInterfaces WireGuard disponíveis:"
            discovered.each_with_index(1) do |iface_name, idx|
              puts "  #{idx}) #{iface_name}"
            end
            print "Selecione uma interface [1-#{discovered.size}] (Padrão: 1): "
            input = (gets || "").strip
            selected_idx = input.to_i? || 1
            selected_idx = 1 if selected_idx < 1 || selected_idx > discovered.size
            @selected_iface_name = discovered[selected_idx - 1]
            return @context.load_interface(@selected_iface_name.not_nil!)
          end
        rescue
          nil
        end
      end

      private def render_menu(iface : Models::Interface)
        online_count = iface.peers.count(&.online?)
        unnamed_count = iface.peers.count { |p| !p.has_name? }
        status_text = iface.active ? "\e[32mativa\e[0m" : "\e[90minativa\e[0m"
        port_str = iface.effective_listen_port.try(&.to_s) || "N/A"

        mode_indicator = @context.remote? ? " \e[36m[REMOTO: #{@context.remote_client.base_url}]\e[0m" : ""
        puts "\n" + ("=" * 64)
        puts "  wgctl - Gerenciador WireGuard (#{iface.name})#{mode_indicator}"
        puts ("=" * 64)
        puts "Interface: \e[1m#{iface.name}\e[0m (#{status_text}) | Endereço: \e[1m#{iface.effective_address}\e[0m | Porta: \e[1m#{port_str}\e[0m"
        
        peer_info = "Peers: \e[1m#{iface.peers.size}\e[0m (\e[32m#{online_count} online\e[0m)"
        if unnamed_count > 0
          peer_info += " | \e[1;33m⚠️  #{unnamed_count} peer(s) sem nome!\e[0m"
        end
        puts peer_info
        puts ("-" * 64)
        puts "  1) Exibir status detalhado dos peers (status)"
        puts "  2) Adicionar novo peer (com alocação automática de IP) [suporta --preshared-key]"
        puts "  3) Nomear ou editar um peer (adicionar nome, descrição, etc.)"
        puts "  4) Gerar configuração de cliente / QR Code (celular)"
        puts "  5) Remover um peer"
        puts "  6) Validar e diagnosticar configurações (check)"
        puts "  7) Migrar comentários legados do script do Nyr (migrate)"
        puts "  8) Aplicar alterações no kernel sem reiniciar (apply)"
        puts "  9) Inicializar novo servidor WireGuard (init)"
        puts "  0) Sair"
        puts ("-" * 64)
      end

      private def handle_status(iface : Models::Interface)
        puts "\n"
        StatusCommand.run(@context, [iface.name])
        wait_enter
      end

      private def handle_add_peer(iface : Models::Interface)
        puts "\n--- Adicionar Novo Peer ---"
        print "Nome do peer (ex: cel-gabriel, notebook, etc.): "
        name = (gets || "").strip
        if name.empty?
          puts "Operação cancelada: nome não pode ser vazio."
          wait_enter
          return
        end

        print "Endereço IP ou 'auto' para o próximo livre [auto]: "
        ip = (gets || "").strip
        ip = "auto" if ip.empty?

        print "Tipo de dispositivo [phone] (phone, laptop, pc, server): "
        device = (gets || "").strip
        device = "phone" if device.empty?

        print "Descrição [opcional]: "
        description = (gets || "").strip

        ctx = @context.dup
        ctx.config_file = iface.config_path
        ctx.interface = iface.name
        ctx.ip = ip
        ctx.device = device
        ctx.description = description unless description.empty?

        begin
          PeerAddCommand.run(ctx, [name, iface.name])
          puts "\nDeseja exibir o QR Code agora para conectar seu smartphone? (S/n): "
          resp = (gets || "").strip.downcase
          if resp.empty? || resp == "s" || resp == "y" || resp == "sim"
            client_ctx = @context.dup
            client_ctx.config_file = iface.config_path
            client_ctx.interface = iface.name
            client_ctx.qr = true
            ClientCommand.run(client_ctx, [name, iface.name])
          end
        rescue ex
          puts "\nErro ao adicionar peer: #{ex.message}"
        end

        wait_enter
      end

      private def handle_edit_peer(iface : Models::Interface)
        puts "\n--- Nomear / Editar Peer ---"
        if iface.peers.empty?
          puts "Nenhum peer encontrado na interface #{iface.name}."
          wait_enter
          return
        end

        puts "Selecione o peer para editar:"
        iface.peers.each_with_index(1) do |p, idx|
          name_tag = p.has_name? ? "\e[1m#{p.name}\e[0m" : "\e[1;33m[SEM NOME]\e[0m"
          desc_tag = p.description ? " - #{p.description}" : ""
          puts "  #{idx}) #{name_tag} (#{p.clean_ips}) [#{p.device || "sem dispositivo"}]#{desc_tag}"
          puts "     Chave pública: #{p.public_key}" unless p.has_name?
        end
        puts "  0) Cancelar"

        print "Escolha o número do peer: "
        choice = (gets || "").strip.to_i?
        return if choice.nil? || choice <= 0 || choice > iface.peers.size

        target_peer = iface.peers[choice - 1]

        puts "\nPressione Enter sem digitar nada para manter o valor atual entre colchetes."
        
        current_name = target_peer.has_name? ? target_peer.name : ""
        print "Nome [#{current_name.empty? ? "sem nome" : current_name}]: "
        new_name = (gets || "").strip

        current_desc = target_peer.description || ""
        print "Descrição [#{current_desc.empty? ? "nenhuma" : current_desc}]: "
        new_desc = (gets || "").strip

        current_device = target_peer.device || ""
        print "Dispositivo [#{current_device.empty? ? "não definido" : current_device}]: "
        new_device = (gets || "").strip

        current_ip = target_peer.clean_ips
        print "IP [#{current_ip}]: "
        new_ip = (gets || "").strip

        ctx = @context.dup
        ctx.config_file = iface.config_path
        ctx.interface = iface.name
        ctx.name = new_name unless new_name.empty?
        ctx.description = new_desc unless new_desc.empty?
        ctx.device = new_device unless new_device.empty?
        ctx.ip = new_ip unless new_ip.empty?

        begin
          # Use public key as identifier to be robust even if peer lacked a name
          PeerEditCommand.run(ctx, [target_peer.public_key, iface.name])
        rescue ex
          puts "\nErro ao editar peer: #{ex.message}"
        end

        wait_enter
      end

      private def handle_client_qr(iface : Models::Interface)
        puts "\n--- Configuração de Cliente e QR Code ---"
        if iface.peers.empty?
          puts "Nenhum peer encontrado na interface #{iface.name}."
          wait_enter
          return
        end

        puts "Selecione o peer:"
        iface.peers.each_with_index(1) do |p, idx|
          name_tag = p.has_name? ? p.name : "[SEM NOME: #{p.public_key[0...8]}...]"
          puts "  #{idx}) #{name_tag} (#{p.clean_ips})"
        end
        puts "  0) Cancelar"

        print "Escolha o peer: "
        choice = (gets || "").strip.to_i?
        return if choice.nil? || choice <= 0 || choice > iface.peers.size

        target_peer = iface.peers[choice - 1]
        peer_id = target_peer.has_name? ? target_peer.name : target_peer.public_key

        puts "\nComo deseja visualizar a configuração do peer '#{target_peer.name}'?"
        puts "  1) Exibir QR Code no terminal (para escanear com o app WireGuard no celular)"
        puts "  2) Exibir arquivo .conf no terminal"
        puts "  3) Salvar em arquivo .conf"
        puts "  0) Cancelar"
        print "Escolha uma opção [1-3]: "
        action = (gets || "").strip

        case action
        when "1"
          client_ctx = @context.dup
          client_ctx.config_file = iface.config_path
          client_ctx.interface = iface.name
          client_ctx.qr = true
          ClientCommand.run(client_ctx, [peer_id, iface.name])
        when "2"
          client_ctx = @context.dup
          client_ctx.config_file = iface.config_path
          client_ctx.interface = iface.name
          ClientCommand.run(client_ctx, [peer_id, iface.name])
        when "3"
          default_filename = "#{target_peer.name}.conf"
          print "Nome do arquivo de saída [#{default_filename}]: "
          outfile = (gets || "").strip
          outfile = default_filename if outfile.empty?

          client_ctx = @context.dup
          client_ctx.config_file = iface.config_path
          client_ctx.interface = iface.name
          client_ctx.output_file = outfile
          ClientCommand.run(client_ctx, [peer_id, iface.name])
        end

        wait_enter
      end

      private def handle_remove_peer(iface : Models::Interface)
        puts "\n--- Remover Peer ---"
        if iface.peers.empty?
          puts "Nenhum peer encontrado na interface #{iface.name}."
          wait_enter
          return
        end

        puts "Selecione o peer a ser removido:"
        iface.peers.each_with_index(1) do |p, idx|
          puts "  #{idx}) #{p.name} (#{p.clean_ips}) [Chave: #{p.public_key[0...16]}...]"
        end
        puts "  0) Cancelar"

        print "Escolha o peer: "
        choice = (gets || "").strip.to_i?
        return if choice.nil? || choice <= 0 || choice > iface.peers.size

        target_peer = iface.peers[choice - 1]

        print "Tem certeza que deseja remover o peer '#{target_peer.name}' permanentemente? (s/N): "
        confirm = (gets || "").strip.downcase
        if confirm == "s" || confirm == "y" || confirm == "sim"
          begin
            ctx = @context.dup
            ctx.config_file = iface.config_path
            ctx.interface = iface.name
            PeerRemoveCommand.run(ctx, [target_peer.public_key, iface.name])
          rescue ex
            puts "Erro ao remover peer: #{ex.message}"
          end
        else
          puts "Remoção cancelada."
        end

        wait_enter
      end

      private def handle_check(iface : Models::Interface)
        puts "\n--- Diagnóstico e Validação ---"
        CheckCommand.run(@context, [iface.name])
        wait_enter
      end

      private def handle_migrate(iface : Models::Interface)
        puts "\n--- Migração de Comentários do Nyr ---"
        MigrateCommand.run(@context, [iface.name])
        wait_enter
      end

      private def handle_apply(iface : Models::Interface)
        puts "\n--- Aplicar Alterações ao Vivo (wg syncconf) ---"
        ApplyCommand.run(@context, [iface.name])
        wait_enter
      end

      private def wait_enter
        print "\nPressione [Enter] para continuar..."
        gets
      end
    end
  end
end
