// Copyright 2024 RISC Zero, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Operations dealing with components and generated code.

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/FunctionInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/IR/OpAsmInterface.td"
include "mlir/Interfaces/CallInterfaces.td"
include "zirgen/Dialect/ZHLT/IR/Dialect.td"
include "zirgen/Dialect/ZHLT/IR/NamedVariadic.td"
include "zirgen/Dialect/ZHLT/IR/Types.td"
include "zirgen/Dialect/ZStruct/IR/Types.td"

include "zirgen/Dialect/ZHLT/IR/Interfaces.td"

def IsPoly : DeclareOpInterfaceMethods<PolyOp>;

// A mlir::func::FuncOp-like operation which allows specification of different types of arguments by names with
// `funcInputs` and `funcOutputs`.
class ZFuncOp<string aspectArg, list<Trait> childTraits = [], string mnemonic = aspectArg # "_func">
    : Op<ZhltDialect, mnemonic,
    // Redefine traits later, since they depend on calculated predicates.
    /*traits=*/[]> {
  string cppClassName = NAME;
  dag funcInputs = (ins);
  dag funcResults = (outs);
  NamedVariadicSnippets inputSnippets = NamedVariadicSnippets<funcInputs>;
  defvar inputSubstSnippets = NamedVariadicSubstSnippets<inputSnippets,
     /*rawTypes=*/ "getFunctionType().getInputs()",
     /*rawValues=*/ "getBody().getArguments()",
     /*segmentSizes=*/ "getInputSegmentSizes()",
     /*buildRawTypes=*/ "rawInputTypes",
     /*buildRawValues=*/ ?,
     /*buildSegmentSizes=*/ "inputSegmentSizes",
     /*cppValueType=*/ "::mlir::BlockArgument",
     /*cppValueRangeType=*/ "::llvm::ArrayRef<::mlir::BlockArgument>">;

  NamedVariadicSnippets resultSnippets = NamedVariadicSnippets<funcResults>;
  defvar resultSubstSnippets = NamedVariadicSubstSnippets<resultSnippets,
     /*rawTypes=*/ "getFunctionType().getResults()",
     /*rawValues=*/ ?,
     /*segmentSizes=*/ "getResultSegmentSizes()",
     /*buildRawTypes=*/ "rawResultTypes",
     /*buildRawValues=*/ ?,
     /*buildSegmentSizes=*/ "resultSegmentSizes",
     /*cppValueType=*/ ?,
     /*cppValueRangeType=*/ ?>;

    let traits = childTraits # [
      CallableOpInterface, FunctionOpInterface, IsolatedFromAbove, OpAsmOpInterface,
       DeclareOpInterfaceMethods<InferResultSegmentSizesOpInterface>,
       PredOpTrait<"has valid ZFunc inputs", inputSubstSnippets.pred>,
       PredOpTrait<"has valid ZFunc outputs", resultSubstSnippets.pred>,
       HasParent<"::mlir::ModuleOp">];

  let arguments = (ins
    SymbolNameAttr:$sym_name,
    TypeAttrOf<FunctionType>: $function_type,
    OptionalAttr<StrAttr>:$sym_visibility,
    OptionalAttr<DictArrayAttr>:$arg_attrs,
    OptionalAttr<DictArrayAttr>:$res_attrs
  );

  string aspect = aspectArg;
  string symPrefix = aspect # "$";
  code quotedSymPrefix = "\"" # symPrefix # "\"";
  let builders = [
    OpBuilder<
      !con(
      (ins CArg<"llvm::StringRef">:$componentId), !con(
         resultSnippets.builderTypeArgs,
         inputSnippets.builderTypeArgs)), [{
      llvm::SmallVector<mlir::Type> rawInputTypes;
      llvm::SmallVector<mlir::Type> rawResultTypes;
      llvm::SmallVector<int32_t> inputSegmentSizes;
      llvm::SmallVector<int32_t> resultSegmentSizes;
      }] # inputSubstSnippets.builderBuildTypes
         # resultSubstSnippets.builderBuildTypes
         # [{
      mlir::FunctionType funcType = $_builder.getFunctionType(rawInputTypes, rawResultTypes);
      build($_builder, $_state, $_builder.getStringAttr( }] # quotedSymPrefix #
              [{+ componentId),
           funcType, /*visibility=*/{}, /*argAttrs=*/{}, /*resAttrs=*/{});
    }]>
  ];
  let regions = (region SizedRegion<1>:$body);
  code extraZFuncClassDeclaration = [{
    //===------------------------------------------------------------------===//
    // CallableOpInterface
    //===------------------------------------------------------------------===//

    /// Returns the region on the current operation that is callable. This may
    /// return null in the case of an external callable object, e.g. an external
    /// function.
    ::mlir::Region *getCallableRegion() { return &getBody(); }

    /// Returns the results types that the callable region produces when
    /// executed.
    llvm::ArrayRef<mlir::Type> getCallableResults() { return getFunctionType().getResults(); }

    //===------------------------------------------------------------------===//
    // FunctionOpInterface Methods
    //===------------------------------------------------------------------===//

    /// Returns the argument types of this function.
    llvm::ArrayRef<mlir::Type> getArgumentTypes() { return getFunctionType().getInputs(); }

    /// Returns the result types of this function.
    llvm::ArrayRef<mlir::Type> getResultTypes() { return getFunctionType().getResults(); }

    /// Component constructors only ever return one value, so we expose this
    /// specialized getter.
    mlir::Type getResultType() { return getResultTypes()[0]; }

    /// Returns the argument attributes for all callable region arguments or
    /// null if there are none.
    ::mlir::ArrayAttr getCallableArgAttrs() {
      return {};
    }

    /// Returns the result attributes for all callable region results or
    /// null if there are none.
    ::mlir::ArrayAttr getCallableResAttrs() {
      return {};
    }

    static ::llvm::StringRef getSymPrefix() { return }] # quotedSymPrefix # [{; }

    void getAsmBlockArgumentNames(::mlir::Region&, ::mlir::OpAsmSetValueNameFn realSetNameFn) {
       // TODO: Should we update tests to call the args "constructParam"?  Or rename the
       // ODS operand?
       auto setNameFn = [&](::mlir::Value value, ::mlir::StringRef name) {
         if (!name.starts_with("constructParam"))
            realSetNameFn(value, name);
       };
       (void)setNameFn;
       }] # inputSubstSnippets.setValueNames # [{
    }
  }]
    # inputSubstSnippets.typeGetters
    # inputSubstSnippets.valueGetters
    # resultSubstSnippets.typeGetters;

  let extraClassDeclaration = extraZFuncClassDeclaration;

  code extraClassDefinition = [{
mlir::ParseResult $cppClass::parse(mlir::OpAsmParser& parser, mlir::OperationState& result) {
  // Dispatch to the FunctionOpInterface provided utility method that parses the
  // function operation.
  auto buildFuncType = [](mlir::Builder& builder,
                          llvm::ArrayRef<mlir::Type> argTypes,
                          llvm::ArrayRef<mlir::Type> results,
                          mlir::function_interface_impl::VariadicFlag,
                          std::string&) { return builder.getFunctionType(argTypes, results); };

  return mlir::function_interface_impl::parseFunctionOp(parser,
                                                        result,
                                                        /*allowVariadic=*/false,
                                                        getFunctionTypeAttrName(result.name),
                                                        buildFuncType,
                                                        getArgAttrsAttrName(result.name),
                                                        getResAttrsAttrName(result.name));
}

void $cppClass::print(mlir::OpAsmPrinter& p) {
  // Dispatch to the FunctionOpInterface provided utility method that prints the
  // function operation.
  mlir::function_interface_impl::printFunctionOp(p,
                                                 *this,
                                                 /*isVariadic=*/false,
                                                 getFunctionTypeAttrName(),
                                                 getArgAttrsAttrName(),
                                                 getResAttrsAttrName());
}

::llvm::SmallVector<int32_t> $cppClass::getResultSegmentSizes() {
  return ::llvm::SmallVector<int32_t>(getNumResults(), 1);
}
  }];
  let hasCustomAssemblyFormat = 1;
}

class ZCallOp<ZFuncOp func, list<Trait> childTraits = []>
    : Op<ZhltDialect, "call_" # func.aspect,
    // Redefine traits later, since they depend on calculated predicates.
    /*traits=*/[]> {
  dag funcInputs = func.funcInputs;
  dag funcResults = func.funcResults;

  // True if this call operation has the "AttrSizedOpreandSegments"
  // trait and thus needs the mlir-native operand segment sizes
  // attribute "operandSegmentSizes" set.
  bit saveOperandSegmentSizes = !not(!empty(!filter(trait, childTraits, !eq(trait, AttrSizedOperandSegments))));

  NamedVariadicSnippets inputSnippets = NamedVariadicSnippets<funcInputs>;
  defvar inputSubstSnippets = NamedVariadicSubstSnippets<inputSnippets,
     /*rawTypes=*/ "getCalleeType().getInputs()",
     /*rawValues=*/ "getOperation()->getOperands()",
     /*segmentSizes=*/ "getInputSegmentSizes()",
     /*buildRawTypes=*/ ?,
     /*buildRawValues=*/ "rawInputValues",
     /*buildSegmentSizes=*/ "inputSegmentSizes",
     /*cppValueType=*/ "::mlir::OpOperand",
     /*cppValueRangeType=*/ "::mlir::OperandRange">;

  NamedVariadicSnippets resultSnippets = NamedVariadicSnippets<funcResults>;
  defvar resultSubstSnippets = NamedVariadicSubstSnippets<resultSnippets,
     /*rawTypes=*/ "getCalleeType().getResults()",
     /*rawValues=*/ "getOperation()->getResults()",
     /*segmentSizes=*/ "getResultSegmentSizes()",
     /*buildRawTypes=*/ "rawResultTypes",
     /*buildRawValues=*/ ?,
     /*buildSegmentSizes=*/ "resultSegmentSizes",
     /*cppValueType=*/ "::mlir::OpResult",
     /*cppValueRangeType=*/ "::mlir::ResultRange">;

   let traits = childTraits # [
       CallOpInterface,
       DeclareOpInterfaceMethods<InferResultSegmentSizesOpInterface>,
       PredOpTrait<"Valid inputs", inputSubstSnippets.pred>,
       PredOpTrait<"Valid outputs", resultSubstSnippets.pred>];

   let arguments = !con(
      (ins FlatSymbolRefAttr:$callee),
      !con(
        funcInputs,
        (ins OptionalAttr<DictArrayAttr>:$arg_attrs,
          OptionalAttr<DictArrayAttr>:$res_attrs)));
   let results = funcResults;

   code builderSaveOperandSegmentSizes = !if(saveOperandSegmentSizes, [{
      $_state.addAttribute(AttrSizedOperandSegments::getOperandSegmentSizeAttr(),
          $_builder.getDenseI32ArrayAttr(inputSegmentSizes));
   }], "");

   let builders = [
      // Build with symbol of callee's component.  In this case,
      // we must explicitly specify result types.
      OpBuilder<
        !con(
           (ins CArg<"llvm::StringRef">:$componentId),
           !con(resultSnippets.builderTypeArgs, inputSnippets.builderValueArgs)),
        [{
          llvm::SmallVector<mlir::Value> rawInputValues;
          llvm::SmallVector<mlir::Type> rawResultTypes;
          llvm::SmallVector<int32_t> inputSegmentSizes;
          llvm::SmallVector<int32_t> resultSegmentSizes;
        }] # resultSubstSnippets.builderBuildTypes
           # inputSubstSnippets.builderBuildValues # [{
          mlir::FunctionType funcType = $_builder.getFunctionType(
                             mlir::ValueRange(rawInputValues).getTypes(), rawResultTypes);
          build($_builder, $_state, $_builder.getAttr<mlir::FlatSymbolRefAttr>(( }] # func.quotedSymPrefix # [{ + componentId).str()),
                funcType,
                rawInputValues,
                inputSegmentSizes,
                resultSegmentSizes);
      }]>,
      // Build given a ZFuncOp.  In this case, we can infer result types
      // and only need operand values.
      OpBuilder<
        !con((ins CArg<func.cppNamespace # "::" # func.cppClassName>:$component), inputSnippets.builderValueArgs),
        [{
          llvm::SmallVector<mlir::Value> rawInputValues;
          llvm::SmallVector<int32_t> inputSegmentSizes;
        }]# inputSubstSnippets.builderBuildValues # [{
          mlir::FunctionType funcType = component.getFunctionType();
          assert(inputSegmentSizes == component.getInputSegmentSizes());
          build($_builder, $_state,
                $_builder.getAttr<mlir::FlatSymbolRefAttr>(component.getSymName()),
                funcType,
                rawInputValues,
                inputSegmentSizes,
                component.getResultSegmentSizes());
       }]>,
       // Build fully specifying raw values and result types
       OpBuilder<(ins
         CArg<"::mlir::FlatSymbolRefAttr">:$callee,
         CArg<"::mlir::FunctionType">:$calleeType,
         CArg<"::mlir::ValueRange">:$operands,
         CArg<"::llvm::ArrayRef<int32_t>">:$inputSegmentSizes,
         CArg<"::llvm::ArrayRef<int32_t>">:$resultSegmentSizes), [{
         build($_builder, $_state, calleeType.getResults(), operands);
         auto& props = $_state.getOrAddProperties<Properties>();
         props.callee = callee;
       }] # builderSaveOperandSegmentSizes>];

  let extraClassDeclaration = [{
    /// Get the argument operands to the called function.
    mlir::Operation::operand_range getArgOperands() {
      return getOperation()->getOperands();
    }

    mlir::MutableOperandRange getArgOperandsMutable() {
      return mlir::MutableOperandRange(getOperation(), 0, getOperation()->getNumOperands());
    }

    /// Return the callee of this operation.
    mlir::CallInterfaceCallable getCallableForCallee() {
      return (*this)->getAttrOfType<mlir::SymbolRefAttr>("callee");
    }

    /// Set the callee for this operation.
    void setCalleeFromCallable(mlir::CallInterfaceCallable callee) {
      (*this)->setAttr("callee", llvm::cast<mlir::SymbolRefAttr>(callee));
    }

    ::mlir::Value getResult() { return getOperation()->getResult(0); }

    ::mlir::FunctionType getCalleeType() {
      return ::mlir::FunctionType::get(getContext(), getOperandTypes(), (*this)->getResultTypes());
    }
  }]
    // Only need to add the type getters; value getters are generated automatically
    // by ODS due to their inclusion to "arguments" and "results".
    # inputSubstSnippets.typeGetters
    # resultSubstSnippets.typeGetters;

  let extraClassDefinition = [{
::llvm::SmallVector<int32_t> $cppClass::getResultSegmentSizes() {
  return {1};
}
  }];

  let assemblyFormat = [{
    $callee `(` operands `)` `:` functional-type(operands, results) attr-dict
  }];
}

// Base component that other aspects are generated from.
def ComponentOp : ZFuncOp</*aspect=*/"",
                          [CodegenSkip, DeclareOpInterfaceMethods<InferInputSegmentSizesOpInterface>],
                          /*mnemonic=*/"component"> {
  let symPrefix = "";
  let summary = "Component declaration";
  let funcInputs = (ins
      Variadic<ZirType>:$constructParam,
      Optional<IsLayoutType>:$layout
  );
  let funcResults = (outs ZirType:$out);
  defvar extra = extraClassDeclaration;
  let extraClassDeclaration = extraZFuncClassDeclaration # [{
    // Returns the given generated aspect of this component.
    template<typename T>
    T getAspect() {
       return mlir::SymbolTable::lookupNearestSymbolFrom<T>(*this, getAspectSymName<T>());
    }

    // Returns the symbol name of the specified generated aspect of this component.
    template<typename T>
    mlir::StringAttr getAspectSymName() {
       return mlir::StringAttr::get(getContext(), T::getSymPrefix() + getName());
    }
  }];
}

def ConstructOp : ZCallOp<ComponentOp, [AttrSizedOperandSegments, DeclareOpInterfaceMethods<InferInputSegmentSizesOpInterface>]> {
  let opName = "construct";
}

def CheckLayoutFuncOp : ZFuncOp<"check_layout", [CodegenSkip, DeclareOpInterfaceMethods<InferInputSegmentSizesOpInterface>]> {
  let summary = "An inlined collection of layout constraints from a circuit entry point";
  let description = [{
    This aspect contains all instances of AliasLayoutOp and all supporting
    operations to compute their operands from a particular circuit entry point.
    This is subsequently used by LayoutDAGAnalysis/GenerateLayoutPass to create
    the ultimate layout of the circuit.
  }];
  let funcInputs = (ins Optional<IsLayoutType>:$layout);
  let hasRegionVerifier = 1;
}

def CheckFuncOp : ZFuncOp<"check", [CodegenSkip, DeclareOpInterfaceMethods<InferInputSegmentSizesOpInterface>]> {
  let summary = "An inlined version of a circuit-wide CheckFuncOp.";
  let description = [{
     This function checks all constraints in the circuit that (not including test constraints).
     All callees are inlined, and all control structures are unrolled into "zll.if"s.

     This is a circuit-wide singleton, and there should only be one non-test instance of this operation.
  }];
  let hasRegionVerifier = 1;
  let extraClassDeclaration = extraZFuncClassDeclaration # [{
     // Ensures all constraints are less than or equal to the provided degree
     mlir::LogicalResult verifyMaxDegree(size_t maxDegree);
  }];
}

def ExecFuncOp : ZFuncOp<"exec", [DeclareOpInterfaceMethods<InferInputSegmentSizesOpInterface>]> {
  let summary = "Executes a component and fills the layout";
  let description = [{
     Also checks constraints unless the --circuit-ndebug option is specified,
  }];
  let funcInputs = (ins
      Variadic<ZirType>:$constructParam,
      Optional<IsLayoutType>:$layout);
  let funcResults = (outs ZirType:$out);
}

def ExecCallOp : ZCallOp<ExecFuncOp, [AttrSizedOperandSegments, DeclareOpInterfaceMethods<InferInputSegmentSizesOpInterface>]>;

def BackFuncOp : ZFuncOp<"back", [DeclareOpInterfaceMethods<InferInputSegmentSizesOpInterface>]> {
  let summary = "Retrieves the value of a component based on its layout";
  let funcInputs = (ins
      Index:$distance,
      Optional<IsLayoutType>:$layout);
  let funcResults = (outs ZirType:$out);
}

def BackCallOp : ZCallOp<BackFuncOp, [MemoryEffects<[MemRead]>, DeclareOpInterfaceMethods<InferInputSegmentSizesOpInterface>]>;


// A FuncOp-like operation that has names associated with
// arguments.  It also allows creating multiple function ops to allow
// them to be handled differently in patterns.  Unlike ZFuncOp, this
// doesn't allow convenient access to argument or result groups by
// name, nor does it verify the types of arguments.
//
class ZLooseFuncOp<string mnemonic, list<Trait> childTraits = []>
    : Op<ZhltDialect, mnemonic,
         childTraits # [CallableOpInterface, FunctionOpInterface, IsolatedFromAbove, OpAsmOpInterface]> {
  string cppClassName = NAME;

  let arguments = (ins
    SymbolNameAttr:$sym_name,
    TypeAttrOf<FunctionType>: $function_type,
    OptionalAttr<StrAttr>:$sym_visibility,
    OptionalAttr<DictArrayAttr>:$arg_attrs,
    OptionalAttr<DictArrayAttr>:$res_attrs
  );

  let builders = [
    OpBuilder<(ins
      "mlir::StringRef":$name, "mlir::FunctionType":$type,
      CArg<"llvm::ArrayRef<llvm::StringRef>", "{}">:$argNames), [{
        $_state.addAttribute(SymbolTable::getSymbolAttrName(),
            $_builder.getStringAttr(name));
        $_state.addAttribute(getFunctionTypeAttrName($_state.name), TypeAttr::get(type));
        $_state.addRegion();
        auto argAttrs = llvm::map_to_vector(argNames, [&](auto argName) -> mlir::Attribute {
            if (argName.empty()) return $_builder.getDictionaryAttr({});
            return $_builder.getDictionaryAttr({$_builder.getNamedAttr("zirgen.argName", $_builder.getStringAttr(argName))});
        });
        $_state.addAttribute(getArgAttrsAttrName($_state.name), $_builder.getArrayAttr(argAttrs));
      }]>];
  let regions = (region SizedRegion<1>:$body);

  let extraClassDeclaration = [{
    // FunctionOpInterface Methods
    ::mlir::Region *getCallableRegion() { return isExternal() ? nullptr : &getBody(); }
    ::llvm::ArrayRef<mlir::Type> getArgumentTypes() { return getFunctionType().getInputs(); }
    ::llvm::ArrayRef<mlir::Type> getResultTypes() { return getFunctionType().getResults(); }
    // OpAsmOpInterface Methods
    void getAsmBlockArgumentNames(::mlir::Region& r, ::mlir::OpAsmSetValueNameFn setNameFn) {
      getZirgenBlockArgumentNames(*this, r, setNameFn);
    }
  }];

  code extraClassDefinition = [{
mlir::ParseResult $cppClass::parse(mlir::OpAsmParser& parser, mlir::OperationState& result) {
  // Dispatch to the FunctionOpInterface provided utility method that parses the
  // function operation.
  auto buildFuncType = [](mlir::Builder& builder,
                          llvm::ArrayRef<mlir::Type> argTypes,
                          llvm::ArrayRef<mlir::Type> results,
                          mlir::function_interface_impl::VariadicFlag,
                          std::string&) { return builder.getFunctionType(argTypes, results); };

  return mlir::function_interface_impl::parseFunctionOp(parser,
                                                        result,
                                                        /*allowVariadic=*/false,
                                                        getFunctionTypeAttrName(result.name),
                                                        buildFuncType,
                                                        getArgAttrsAttrName(result.name),
                                                        getResAttrsAttrName(result.name));
}

void $cppClass::print(mlir::OpAsmPrinter& p) {
  // Dispatch to the FunctionOpInterface provided utility method that prints the
  // function operation.
  mlir::function_interface_impl::printFunctionOp(p,
                                                 *this,
                                                 /*isVariadic=*/false,
                                                 getFunctionTypeAttrName(),
                                                 getArgAttrsAttrName(),
                                                 getResAttrsAttrName());
}

  }];
  let hasCustomAssemblyFormat = 1;
}

class ZLooseCallOp<ZLooseFuncOp func, string mnemonic, list<Trait> childTraits = []>
    : Op<ZhltDialect, mnemonic, childTraits # [CallOpInterface]> {
   let arguments =
      (ins FlatSymbolRefAttr: $callee,
           TypeAttrOf<FunctionType>: $callee_type,
           Variadic<AnyType>: $operands,
           OptionalAttr<DictArrayAttr>:$arg_attrs,
           OptionalAttr<DictArrayAttr>:$res_attrs);
   let results = (outs Variadic<AnyType>: $results);
   let builders = [
      // Build given a ZLooseFuncOp.  In this case, we can infer result types
      // and only need operand values.
      OpBuilder<
        (ins CArg<func.cppNamespace # "::" # func.cppClassName>: $component,
             CArg<"mlir::ValueRange", "{}">:$operands), [{
          mlir::FunctionType funcType = component.getFunctionType();
          build($_builder, $_state,
                funcType.getResults(),
                $_builder.getAttr<mlir::FlatSymbolRefAttr>(component.getSymName()),
                TypeAttr::get(funcType),
                operands,
                mlir::ArrayAttr(),
                mlir::ArrayAttr());
       }]>];
  let extraClassDeclaration = [{
    /// Get the argument operands to the called function.
    mlir::Operation::operand_range getArgOperands() {
      return getOperation()->getOperands();
    }

    mlir::MutableOperandRange getArgOperandsMutable() {
      return mlir::MutableOperandRange(getOperation(), 0, getOperation()->getNumOperands());
    }

    /// Return the callee of this operation.
    mlir::CallInterfaceCallable getCallableForCallee() {
      return (*this)->getAttrOfType<mlir::SymbolRefAttr>("callee");
    }

    /// Set the callee for this operation.
    void setCalleeFromCallable(mlir::CallInterfaceCallable callee) {
      (*this)->setAttr("callee", llvm::cast<mlir::SymbolRefAttr>(callee));
    }
  }];
  let assemblyFormat = [{
    $callee `(` operands `)` `:` functional-type(operands, results) attr-dict
  }];
}

def StepFuncOp : ZLooseFuncOp<"step_func"> {
  let summary = "A function that's intended to be used to populate the witness";
}

def StepCallOp : ZLooseCallOp<StepFuncOp, "call_step">;

def ValidityRegsFuncOp : ZLooseFuncOp<"validity_regs_func"> {
  let summary = "Evaluates the validity polynomial from a layout";
  let hasRegionVerifier = 1;
}

def ValidityTapsFuncOp : ZLooseFuncOp<"validity_taps_func"> {
  let summary = "Evaluates the validity polynomial from an array of taps";
  let hasRegionVerifier = 1;
}

