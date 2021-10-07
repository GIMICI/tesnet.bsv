defmodule BSV.TxBuilderTest do
  use ExUnit.Case, async: true
  alias BSV.TxBuilder
  alias BSV.{Address, Contract, KeyPair, OutPoint, PrivKey, Script, TxOut, Util, UTXO}
  alias BSV.Contract.{P2PKH, Raw}
  doctest TxBuilder

  @wif "KyGHAK8MNohVPdeGPYXveiAbTfLARVrQuJVtd3qMqN41UEnTWDkF"
  @keypair KeyPair.from_privkey(PrivKey.from_wif!(@wif))
  @address Address.from_pubkey(@keypair.pubkey)

  describe "add_input/2" do
    test "appends an input contract" do
      builder = TxBuilder.add_input(%TxBuilder{}, P2PKH.unlock(%UTXO{}, %{keypair: @keypair}))
      assert length(builder.inputs) == 1
      assert %Contract{mfa: {P2PKH, :unlocking_script, _}, subject: %UTXO{}} = List.first(builder.inputs)
    end
  end

  describe "add_output/2" do
    test "appends an input contract" do
      builder = TxBuilder.add_output(%TxBuilder{}, P2PKH.lock(1000, %{address: @address}))
      assert length(builder.outputs) == 1
      assert %Contract{mfa: {P2PKH, :locking_script, _}, subject: 1000} = List.first(builder.outputs)
    end
  end

  describe "change_to/2" do
    test "set P2PKH change script from address" do
      builder = TxBuilder.change_to(%TxBuilder{}, @address)
      assert %Script{chunks: [:OP_DUP, :OP_HASH160, _pubkeyhash, :OP_EQUALVERIFY, :OP_CHECKSIG]} = builder.change_script
    end

    test "set P2PKH change script from address string" do
      builder = TxBuilder.change_to(%TxBuilder{}, Address.to_string(@address))
      assert %Script{chunks: [:OP_DUP, :OP_HASH160, _pubkeyhash, :OP_EQUALVERIFY, :OP_CHECKSIG]} = builder.change_script
    end
  end

  describe "input_sum/1" do
    test "sums the satoshis of all input UTXOs" do
      builder = %TxBuilder{inputs: [
        P2PKH.unlock(%UTXO{txout: %TxOut{satoshis: 1000}}, %{}),
        P2PKH.unlock(%UTXO{txout: %TxOut{satoshis: 1123}}, %{})
      ]}
      assert TxBuilder.input_sum(builder) == 2123
    end

    test "returns 0 when no inputs" do
      assert TxBuilder.input_sum(%TxBuilder{}) == 0
    end
  end

  describe "output_sum/1" do
    test "sums the satoshis of all outputs" do
      builder = %TxBuilder{outputs: [
        P2PKH.lock(1000, %{}),
        P2PKH.lock(1123, %{})
      ]}
      assert TxBuilder.output_sum(builder) == 2123
    end

    test "returns 0 when no outputs" do
      assert TxBuilder.output_sum(%TxBuilder{}) == 0
    end
  end

  describe "sort/1" do
    setup do
      vectors = File.read!("test/vectors/bip69.json") |> Jason.decode!()
      {:ok, vectors: vectors}
    end

    test "bip69 input test vectors", %{vectors: vectors} do
      for v <- vectors["inputs"] do
        inputs = Enum.map v["inputs"], fn i ->
          utxo = %UTXO{outpoint: %OutPoint{
            hash: Util.decode!(i["txId"], :hex) |> Util.reverse_bin(),
            index: i["vout"]
          }}
          P2PKH.unlock(utxo, %{})
        end

        builder = TxBuilder.sort(%TxBuilder{inputs: inputs})
        indexes = Enum.map(builder.inputs, fn i ->
          Enum.find_index(inputs, & &1.subject.outpoint == i.subject.outpoint)
        end)

        assert indexes == v["expected"], v["description"]
      end
    end

    test "bip69 output test vectors", %{vectors: vectors} do
      for v <- vectors["outputs"] do
        outputs = Enum.map v["outputs"], fn o ->
          script = Script.from_binary!(o["script"], encoding: :hex)
          Raw.lock(o["value"], %{script: script})
        end

        builder = TxBuilder.sort(%TxBuilder{outputs: outputs})
        indexes = Enum.map(builder.outputs, fn i ->
          Enum.find_index(outputs, & &1.mfa == i.mfa and &1.subject == i.subject)
        end)

        assert indexes == v["expected"] , v["description"]
      end
    end
  end

end