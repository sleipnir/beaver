defmodule Manx.Lowering do
  alias Beaver.MLIR

  @doc """
  Run passes to compile IR generated from Nx expressions, mostly in TOSA and some LinAlg. The results should be in LLVM.
  """
  def tosa_cpu(op) do
    import MLIR.{Transforms, Conversion}

    op
    |> canonicalize
    |> MLIR.Pass.Composer.nested("func.func", fn pm ->
      MLIR.Pass.pipeline!(pm, "tosa-make-broadcastable")
    end)
    |> MLIR.Pass.Composer.run!(dump_if_fail: true)
    |> MLIR.Operation.verify!(dump_if_fail: true)
    |> MLIR.Pass.Composer.nested("func.func", fn pm ->
      MLIR.Pass.pipeline!(pm, "tosa-layerwise-constant-fold")
    end)
    |> cse
    |> MLIR.Pass.Composer.run!(dump: false)
    |> tosa_to_scf
    |> tosa_to_arith
    |> tosa_to_tensor()
    |> convert_tensor_to_linalg()
    |> MLIR.Pass.Composer.nested("func.func", [
      tosa_to_linalg(),
      linalg_fuse_elementwise_ops()
    ])
    |> MLIR.Pass.Composer.run!(dump_if_fail: true)
    |> MLIR.Pass.Composer.nested("func.func", [
      linalg_bufferize(),
      convert_linalg_to_loops(),
      lower_affine(),
      convert_math_to_llvm(),
      convert_arith_to_llvm(),
      convert_scf_to_cf(),
      "arith-expand",
      "memref-expand"
    ])
    |> MLIR.Pass.Composer.nested("func.func", fn pm ->
      MLIR.Pass.pipeline!(pm, "tensor-bufferize")
    end)
    |> MLIR.Pass.Composer.pipeline("arith-bufferize,func-bufferize")
    |> MLIR.Pass.Composer.nested("func.func", fn pm ->
      MLIR.Pass.pipeline!(pm, "llvm-request-c-wrappers")
    end)
    |> convert_complex_to_standard()
    |> convert_vector_to_llvm
    |> convert_memref_to_llvm
    |> convert_complex_to_llvm()
    |> convert_func_to_llvm
    |> reconcile_unrealized_casts
    |> MLIR.Pass.Composer.run!(dump_if_fail: true)
  end
end
