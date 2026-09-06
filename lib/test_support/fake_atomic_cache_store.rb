# frozen_string_literal: true
#
# FakeAtomicCacheStore — substituto do MemoryStore para o teste
# 'concurrent reserves: between N attempts for quota M, exactly M succeed'.
#
# O MemoryStore original faz read-modify-write no increment (NAO ATOMICO).
# Com 10 threads e mais nucleos, 2 threads leem o mesmo valor e causam
# overcount (6 reservas quando max=5) — o teste flakeia.
#
# Este fake usa um Hash protegido por Mutex para cada operacao: write,
# read, increment, decrement sao atomicos por mutex, garantindo que no
# teste 'concurrent reserves' exatamente M threads alcancem sucessos.
#
# O increment usa compute_if_absent com mutex: a leitura do valor atual,
# o calculo do novo valor e a escrita acontecem dentro do mesmo lock,
# garantindo atomicidade (CAS) entre threads.
#
# Whitelist: lib/test_support/fake_atomic_cache_store.rb,
#            test/setup/phase3_llm_test.rb,
#            tmp/validate_standalone.rb.

module TestSupport
  # Cache store com incremento atomico entre threads (mutex + hash).
  # Substitui o MemoryStore no teste de concorrencia para eliminar o flake.
  #
  # Interface compativel com ActiveSupport::Cache::Store: write, read,
  # increment, decrement, clear, delete.
  class FakeAtomicCacheStore < ActiveSupport::Cache::Store
    def initialize
      @store = {}
      @mutex = Mutex.new
    end

    def read(key, _options = nil)
      @mutex.synchronize { @store[key] }
    end

    def write(key, value, **_kwargs)
      @mutex.synchronize { @store[key] = value }
      true
    end

    # Increment atomico via compute_if_absent com mutex.
    #
    # A operação completa (leitura do valor atual + soma + escrita do novo
    # valor) ocorre dentro de um único lock, garantindo que dois threads
    # não leiam o mesmo valor e sobrescrevam — comportamento equivalente
    # ao increment atômico do SolidCache em produção.
    #
    # Suporta unless_exist: true (só opera se a chave ainda não existir).
    # Suporta max: rejeita (retorna nil) se o novo valor ultrapassar o limite.
    def increment(key, amount = 1, **kwargs)
      unless_exist = kwargs.fetch(:unless_exist, false)
      max = kwargs[:max]

      @mutex.synchronize do
        if unless_exist && @store.key?(key)
          return nil
        end

        current = @store[key]
        current = current.to_i if current
        new_val = (current || 0) + amount.to_i

        if max && new_val > max.to_i
          return nil
        end

        @store[key] = new_val
        new_val
      end
    end

    def decrement(key, amount = 1, **_kwargs)
      @mutex.synchronize do
        current = @store[key]
        current = current.to_i if current
        new_val = (current || 0) - amount.to_i
        @store[key] = new_val
        new_val
      end
    end

    def clear(**_kwargs)
      @mutex.synchronize { @store.clear }
    end

    def delete(key, **_kwargs)
      @mutex.synchronize { @store.delete(key) }
    end
  end
end
