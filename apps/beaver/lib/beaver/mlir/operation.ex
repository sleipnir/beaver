defmodule Beaver.MLIR.Operation do
  alias Beaver.MLIR
  alias Beaver.MLIR.CAPI
  import Beaver.MLIR.CAPI
  require Logger

  @doc """
  Create a new operation from a operation state
  """
  def create(%MLIR.Operation.State{} = state) do
    state |> MLIR.Operation.State.create() |> create
  end

  def create(state) do
    state |> Beaver.Native.ptr() |> Beaver.Native.bag(state) |> MLIR.CAPI.mlirOperationCreate()
  end

  @doc """
  Create a new operation from arguments and insert to managed insertion point
  """

  def create(op_name, %Beaver.DSL.SSA{
        block: %MLIR.CAPI.MlirBlock{} = block,
        arguments: arguments,
        results: results,
        filler: filler
      }) do
    filler =
      if is_function(filler, 0) do
        [regions: filler]
      else
        []
      end

    create(op_name, arguments ++ [result_types: results] ++ filler, block)
  end

  def create(op_name, %Beaver.DSL.Op.Prototype{
        operands: operands,
        attributes: attributes,
        results: results
      }) do
    create(op_name, operands ++ attributes ++ [result_types: results])
  end

  # one single value, usually a terminator
  def create(op_name, %MLIR.Value{} = op) do
    create(op_name, [op])
  end

  def create(op_name, arguments, %MLIR.CAPI.MlirBlock{} = block) when is_list(arguments) do
    op = do_create(op_name, arguments)
    Beaver.MLIR.CAPI.mlirBlockAppendOwnedOperation(block, op)
    op
  end

  def results(%MLIR.CAPI.MlirOperation{} = op) do
    case CAPI.mlirOperationGetNumResults(op) |> Beaver.Native.to_term() do
      0 ->
        op

      1 ->
        CAPI.mlirOperationGetResult(op, 0)

      n when n > 1 ->
        for i <- 0..(n - 1)//1 do
          CAPI.mlirOperationGetResult(op, i)
        end
    end
  end

  def results({:deferred, {_func_name, _arguments}} = deferred) do
    deferred
  end

  defp do_create(op_name, arguments) when is_binary(op_name) and is_list(arguments) do
    location = MLIR.Managed.Location.get()

    state = %MLIR.Operation.State{name: op_name, location: location}
    state = Enum.reduce(arguments, state, &MLIR.Operation.State.add_argument(&2, &1))

    state
    |> MLIR.Operation.State.create()
    |> MLIR.Operation.create()
  end

  @default_verify_opts [dump: false, dump_if_fail: false]
  def verify!(op, opts \\ @default_verify_opts) do
    with {:ok, op} <-
           verify(op, opts ++ [should_raise: true]) do
      op
    else
      :fail -> raise "MLIR operation verification failed"
    end
  end

  def verify(op, opts \\ @default_verify_opts) do
    dump = opts |> Keyword.get(:dump, false)
    dump_if_fail = opts |> Keyword.get(:dump_if_fail, false)
    is_success = from_module(op) |> MLIR.CAPI.mlirOperationVerify() |> Beaver.Native.to_term()

    if dump do
      Logger.warning("Start dumping op not verified. This might crash.")
      dump(op)
    end

    if is_success do
      {:ok, op}
    else
      if dump_if_fail do
        Logger.info("Start printing op failed to pass the verification. This might crash.")
        Logger.info(MLIR.to_string(op))
      end

      :fail
    end
  end

  def dump(op) do
    op |> from_module |> mlirOperationDump()
    op
  end

  @doc """
  Verify the op and dump it. It raises if the verification fails.
  """
  def dump!(%MLIR.CAPI.MlirOperation{} = op) do
    verify!(op)
    mlirOperationDump(op)
    op
  end

  def name(%MLIR.CAPI.MlirOperation{} = operation) do
    MLIR.CAPI.mlirOperationGetName(operation)
    |> MLIR.CAPI.mlirIdentifierStr()
    |> MLIR.StringRef.extract()
  end

  def from_module(module = %MLIR.Module{}) do
    CAPI.mlirModuleGetOperation(module)
  end

  def from_module(%CAPI.MlirOperation{} = op) do
    op
  end
end
