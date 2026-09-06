# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/discord/thread_event_proxy"

class ThreadEventProxyTest < ActiveSupport::TestCase
  test "edit_response envia NOVA mensagem na thread (Channel nao edita)" do
    original_event = mock("original_event")
    original_channel = stub(id: "456")
    thread_channel = stub(id: "789")

    guild = stub(channels: [thread_channel])
    original_event.stubs(:channel).returns(original_channel)
    original_channel.stubs(:guild).returns(guild)

    # API real da gem: Channel so tem send_message(posicional); a thread recebe a msg nova
    thread_channel.expects(:send_message).with("resposta")

    proxy = Discord::ThreadEventProxy.new(original_event, "789")
    proxy.edit_response(content: "resposta")
  end

  test "edit_response nao faz fallback silencioso quando thread nao encontrada" do
    original_event = mock("original_event")
    original_channel = stub(id: "456")
    
    # Nao encontra thread (canais vazios); guild.id e usado na mensagem de erro
    guild = stub(channels: [], id: "111")
    original_event.stubs(:channel).returns(original_channel)
    original_channel.stubs(:guild).returns(guild)
    
    original_event.expects(:edit_response).never
    Rails.logger.expects(:error).at_least_once

    proxy = Discord::ThreadEventProxy.new(original_event, "789")

    assert_raises(Discord::ThreadChannelUnresolvedError) do
      proxy.edit_response(content: "resposta")
    end
  end

  test "send_message envia para a thread quando canal e encontrado" do
    original_event = mock("original_event")
    original_channel = stub(id: "456")
    thread_channel = stub(id: "789", respond_to?: true)

    guild = stub(channels: [thread_channel])
    original_event.stubs(:channel).returns(original_channel)
    original_channel.stubs(:guild).returns(guild)

    # Proxy mapeia keyword -> posicional da gem (content, tts=false, embed=nil, ...)
    thread_channel.expects(:send_message).with("msg2", false, nil, nil, nil, nil, nil, 0)

    proxy = Discord::ThreadEventProxy.new(original_event, "789")
    proxy.send_message(content: "msg2")
  end

  # ===========================================================================
  # HOTFIX-THREAD-PROXY — respond() vai para a thread, nunca para o canal pai
  # ===========================================================================
  # Causa-raiz (bug de producao 06/09 03:34 UTC): thread_event_proxy.rb:38-52
  # chamava thread_channel.respond(content), mas Discordrb::Channel NAO tem
  # respond (existe apenas em MessageEvent/Respondable como alias de send_message,
  # em Message e em Interaction). Channel tem send_message(posicional).
  # => NoMethodError => rescue silencioso => fallback @original_event.respond
  # => resposta no CANAL PAI ao inves da thread.
  #
  # Verificacao realizada na gem 3.8.0:
  #   lib/discordrb/data/channel.rb:483 send_message(content, tts=false, embed=nil, ...)
  #     -> metodo posicional, NÃO keyword.
  #   lib/discordrb/events/message.rb:94 alias_method :respond, :send_message
  #     -> apenas no modulo Respondable (MessageEvent, MessageIDEvent), nao em Channel.
  #   lib/discordrb/data/interaction.rb:229 edit_response(content:, ...) -> so em Interaction.
  #
  # A decisao de design aqui (documentada no implementacao):
  #   - Se a thread channel existe: respond -> thread_channel.send_message(content)
  #     (posicional, adptado da API real da gem).
  #   - Se a thread channel NAO foi encontrada (guild.channels.find nil, ex. cache do
  #     gateway nao refletiu a thread recem-criada): NAO cai em fallback silencioso
  #     para o canal pai. Levanta erro nomeado (ThreadChannelUnresolvedError) com log
  #     de ERROR; o rescue do handle_message (L367/220) ja devolve "⚠️ Erro ao processar"
  #     para o usuario, que e melhor que resposta no canal errado (bug original).
  #     Alternativa avaliada e REJEITADA: responder no canal pai silenciosamente —
  #     entrega mensagem no lugar errado; preferivel erro visivel para o usuario e
  #     log de DEBUG para o mantenedor. Se futuramente se quiser o canal pai como
  #     fallback de contingencia, essa escolha deve serrevisada explicitamente (com
  #     log WARN e flag de configuracao), nao como rescue generico.
  #
  # NOTA: Discordrb Channel#start_thread retorna Channel da thread; o
  # guild.channels.find pode nao listar thread recem-criada (cache do gateway).
  # Esse teste cobre o cenario find nil com fallback logado.
  # ===========================================================================

  test "respond envia para a thread quando canal e encontrado (NUNCA canal pai)" do
    original_event = mock("original_event")
    original_channel = stub(id: "456")
    thread_channel = stub(id: "789")

    guild = stub(channels: [thread_channel])
    original_event.stubs(:channel).returns(original_channel)
    original_channel.stubs(:guild).returns(guild)

    # O original_event NAO deve receber respond (canal pai)
    original_event.expects(:respond).never

    # A thread channel recebe send_message (API real da gem: posicional)
    thread_channel.expects(:send_message).with("resposta da thread")

    proxy = Discord::ThreadEventProxy.new(original_event, "789")
    proxy.respond("resposta da thread")
  end

  test "respond quando thread nao encontrada: erro nomeado, nao canal pai silencioso" do
    original_event = mock("original_event")
    original_channel = stub(id: "456")

    guild = stub(channels: [], id: "111")
    original_event.stubs(:channel).returns(original_channel)
    original_channel.stubs(:guild).returns(guild)

    original_event.expects(:respond).never
    Rails.logger.expects(:error).at_least_once

    proxy = Discord::ThreadEventProxy.new(original_event, "789")

    assert_raises(Discord::ThreadChannelUnresolvedError) do
      proxy.respond("mensagem")
    end
  end

  test "respond sem channel_id: usa respond do original (comportamento existente preservado)" do
    original_event = mock("original_event")
    original_event.expects(:respond).with("direto no original")

    proxy = Discord::ThreadEventProxy.new(original_event, nil)
    proxy.respond("direto no original")
  end
end
