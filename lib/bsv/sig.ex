defmodule BSV.Sig do
  @moduledoc """
  TODO
  """
  use Bitwise
  alias BSV.{Hash, OutPoint, PrivKey, PubKey, Script, Tx, TxOut, VarInt}

  @typedoc "TODO"
  @type preimage() :: binary()

  @typedoc "TODO"
  @type sighash() :: <<_::256>>

  @typedoc "TODO"
  @type sighash_type() :: integer()

  @typedoc "TODO"
  @type signature() :: binary()

  @sighash_all 0x01
  @sighash_none 0x02
  @sighash_single 0x03
  @sighash_forkid 0x40
  @sighash_anyonecanpay 0x80

  @default_sighash @sighash_all ||| @sighash_forkid

  defguard sighash_all?(sighash_type)
    when (sighash_type &&& 31) == @sighash_all

  defguard sighash_none?(sighash_type)
    when (sighash_type &&& 31) == @sighash_none

  defguard sighash_single?(sighash_type)
    when (sighash_type &&& 31) == @sighash_single

  defguard sighash_forkid?(sighash_type)
    when (sighash_type &&& @sighash_forkid) != 0

  defguard sighash_anyone_can_pay?(sighash_type)
    when (sighash_type &&& @sighash_anyonecanpay) != 0

  @doc """
  TODO
  """
  @spec preimage(Tx.t(), non_neg_integer(), TxOut.t(), sighash_type()) :: preimage()
  def preimage(%Tx{inputs: inputs} = tx, vin, %TxOut{} = txout, sighash_type)
    when sighash_forkid?(sighash_type)
  do
    input = Enum.at(inputs, vin)

    # Input prevouts/nSequence
    prevouts_hash = hash_prevouts(tx.inputs, sighash_type)
    sequence_hash = hash_sequence(tx.inputs, sighash_type)

    # outpoint (32-byte hash + 4-byte little endian)
    outpoint = OutPoint.to_binary(input.prev_out)

    # subscript
    subscript = txout.script
    |> Script.to_binary()
    |> VarInt.encode_binary()

    # Outputs (none/one/all, depending on flags)
    outputs_hash = hash_outputs(tx.outputs, vin, sighash_type)

    <<
      tx.version::little-32,
      prevouts_hash::binary,
      sequence_hash::binary,
      outpoint::binary,
      subscript::binary,
      txout.satoshis::little-64,
      input.sequence::little-32,
      outputs_hash::binary,
      tx.lock_time::little-32,
      (sighash_type >>> 0)::little-32
    >>
  end

  def preimage(%Tx{} = _tx, _vin, %TxOut{} = _txout, _sighash_type),
    do: raise "Legacy Sighash algorithm not implemented yet."

  @doc """
  TODO
  """
  @spec sighash(Tx.t(), non_neg_integer(), TxOut.t(), sighash_type()) :: sighash()
  def sighash(%Tx{} = tx, vin, %TxOut{} = txout, sighash_type \\ @default_sighash) do
    tx
    |> preimage(vin, txout, sighash_type)
    |> Hash.sha256_sha256()
  end

  @doc """
  TODO
  """
  @spec sign(Tx.t(), non_neg_integer(), TxOut.t(), PrivKey.t(), keyword()) :: signature()
  def sign(%Tx{} = tx, vin, %TxOut{} = txout, %PrivKey{d: privkey}, opts \\ []) do
    sighash_type = Keyword.get(opts, :sighash_type, @default_sighash)

    tx
    |> sighash(vin, txout, sighash_type)
    |> Curvy.sign(privkey, hash: false)
    |> Kernel.<>(<<sighash_type>>)
  end

  @doc """
  TODO
  """
  @spec verify(signature(), Tx.t(), non_neg_integer(), TxOut.t(), PubKey.t()) :: boolean() | :error
  def verify(signature, %Tx{} = tx, vin, %TxOut{} = txout, %PubKey{} = pubkey) do
    sig_length = byte_size(signature) - 1
    <<sig::binary-size(sig_length), sighash_type>> = signature
    message = sighash(tx, vin, txout, sighash_type)
    Curvy.verify(sig, message, PubKey.to_binary(pubkey), hash: false)
  end

  # TODO
  defp hash_prevouts(_inputs, sighash_type)
    when sighash_anyone_can_pay?(sighash_type),
    do: <<0::256>>

  defp hash_prevouts(inputs, _sighash_type) do
    inputs
    |> Enum.reduce(<<>>, & &2 <> OutPoint.to_binary(&1.prev_out))
    |> Hash.sha256_sha256()
  end

  # TODO
  defp hash_sequence(_inputs, sighash_type)
    when sighash_anyone_can_pay?(sighash_type)
    or sighash_single?(sighash_type)
    or sighash_none?(sighash_type),
    do: <<0::256>>

  defp hash_sequence(inputs, _sighash_type) do
    inputs
    |> Enum.reduce(<<>>, & &2 <> <<&1.sequence::little-32>>)
    |> Hash.sha256_sha256()
  end

  # TODO
  defp hash_outputs(outputs, vin, sighash_type)
    when sighash_single?(sighash_type)
    and vin < length(outputs)
  do
    outputs
    |> Enum.at(vin)
    |> TxOut.to_binary()
    |> Hash.sha256_sha256()
  end

  defp hash_outputs(outputs, _index, sighash_type)
    when not sighash_none?(sighash_type)
  do
    outputs
    |> Enum.reduce(<<>>, & &2 <> TxOut.to_binary(&1))
    |> Hash.sha256_sha256()
  end

  defp hash_outputs(_outputs, _index, _sighash_type),
    do: :binary.copy(<<0>>, 32)

end