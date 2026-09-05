# frozen_string_literal: true

# Reusable behavior checks for every sender-core state-store backend.
module StateStoreContract
  def test_state_store_contract_supports_atomic_update
    store = build_state_store

    store.update(:counter, default: 0) { |value| value + 1 }

    assert_equal 1, store.read(:counter)
  end

  def test_state_store_contract_rejects_nil_keys
    store = build_state_store

    assert_raises(ArgumentError) { store.read(nil) }
    assert_raises(ArgumentError) { store.write(nil, :value) }
  end

  private

  def build_state_store
    raise NotImplementedError, "contract consumers must provide #build_state_store"
  end
end
