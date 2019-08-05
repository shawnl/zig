/*
 * Copyright (c) 2015 Andrew Kelley
 *
 * This file is part of zig, which is MIT licensed.
 * See http://opensource.org/licenses/MIT
 */

#ifndef ZIG_ALL_TYPES_HPP
#define ZIG_ALL_TYPES_HPP

#include "list.hpp"
#include "buffer.hpp"
#include "cache_hash.hpp"
#include "zig_llvm.h"
#include "hash_map.hpp"
#include "errmsg.hpp"
#include "bigint.hpp"
#include "bigfloat.hpp"
#include "target.hpp"
#include "tokenizer.hpp"
#include "libc_installation.hpp"

struct AstNode;
struct ZigFn;
struct Scope;
struct ScopeBlock;
struct ScopeFnDef;
struct ZigType;
struct ZigVar;
struct ErrorTableEntry;
struct BuiltinFnEntry;
struct TypeStructField;
struct CodeGen;
struct ConstExprValue;
struct IrInstruction;
struct IrInstructionCast;
struct IrInstructionAllocaGen;
struct IrBasicBlock;
struct ScopeDecls;
struct ZigWindowsSDK;
struct Tld;
struct TldExport;
struct IrAnalyze;
struct ResultLoc;
struct ResultLocPeer;
struct ResultLocPeerParent;
struct ResultLocBitCast;

enum X64CABIClass {
    X64CABIClass_Unknown,
    X64CABIClass_MEMORY,
    X64CABIClass_INTEGER,
    X64CABIClass_SSE,
};

struct IrExecutable {
    ZigList<IrBasicBlock *> basic_block_list;
    Buf *name;
    ZigFn *name_fn;
    size_t mem_slot_count;
    size_t next_debug_id;
    size_t *backward_branch_count;
    size_t *backward_branch_quota;
    ZigFn *fn_entry;
    Buf *c_import_buf;
    AstNode *source_node;
    IrExecutable *parent_exec;
    IrExecutable *source_exec;
    IrAnalyze *analysis;
    Scope *begin_scope;
    ZigList<Tld *> tld_list;

    IrInstruction *coro_handle;
    IrInstruction *atomic_state_field_ptr; // this one is shared and in the promise
    IrInstruction *coro_result_ptr_field_ptr;
    IrInstruction *coro_result_field_ptr;
    IrInstruction *await_handle_var_ptr; // this one is where we put the one we extracted from the promise
    IrBasicBlock *coro_early_final;
    IrBasicBlock *coro_normal_final;
    IrBasicBlock *coro_suspend_block;
    IrBasicBlock *coro_final_cleanup_block;
    ZigVar *coro_allocator_var;

    bool invalid;
    bool is_inline;
    bool is_generic_instantiation;
};

enum OutType {
    OutTypeUnknown,
    OutTypeExe,
    OutTypeLib,
    OutTypeObj,
};

enum ConstParentId {
    ConstParentIdNone,
    ConstParentIdStruct,
    ConstParentIdErrUnionCode,
    ConstParentIdErrUnionPayload,
    ConstParentIdOptionalPayload,
    ConstParentIdArray,
    ConstParentIdUnion,
    ConstParentIdScalar,
};

struct ConstParent {
    ConstParentId id;

    union {
        struct {
            ConstExprValue *array_val;
            size_t elem_index;
        } p_array;
        struct {
            ConstExprValue *struct_val;
            size_t field_index;
        } p_struct;
        struct {
            ConstExprValue *err_union_val;
        } p_err_union_code;
        struct {
            ConstExprValue *err_union_val;
        } p_err_union_payload;
        struct {
            ConstExprValue *optional_val;
        } p_optional_payload;
        struct {
            ConstExprValue *union_val;
        } p_union;
        struct {
            ConstExprValue *scalar_val;
        } p_scalar;
    } data;
};

struct ConstStructValue {
    ConstExprValue *fields;
};

struct ConstUnionValue {
    BigInt tag;
    ConstExprValue *payload;
};

enum ConstArraySpecial {
    ConstArraySpecialNone,
    ConstArraySpecialUndef,
    ConstArraySpecialBuf,
};

struct ConstArrayValue {
    ConstArraySpecial special;
    union {
        struct {
            ConstExprValue *elements;
        } s_none;
        Buf *s_buf;
    } data;
};

enum ConstPtrSpecial {
    // Enforce explicitly setting this ID by making the zero value invalid.
    ConstPtrSpecialInvalid,
    // The pointer is a reference to a single object.
    ConstPtrSpecialRef,
    // The pointer points to an element in an underlying array.
    ConstPtrSpecialBaseArray,
    // The pointer points to a field in an underlying struct.
    ConstPtrSpecialBaseStruct,
    // The pointer points to the error set field of an error union
    ConstPtrSpecialBaseErrorUnionCode,
    // The pointer points to the payload field of an error union
    ConstPtrSpecialBaseErrorUnionPayload,
    // The pointer points to the payload field of an optional
    ConstPtrSpecialBaseOptionalPayload,
    // This means that we did a compile-time pointer reinterpret and we cannot
    // understand the value of pointee at compile time. However, we will still
    // emit a binary with a compile time known address.
    // In this case index is the numeric address value.
    ConstPtrSpecialHardCodedAddr,
    // This means that the pointer represents memory of assigning to _.
    // That is, storing discards the data, and loading is invalid.
    ConstPtrSpecialDiscard,
    // This is actually a function.
    ConstPtrSpecialFunction,
    // This means the pointer is null. This is only allowed when the type is ?*T.
    // We use this instead of ConstPtrSpecialHardCodedAddr because often we check
    // for that value to avoid doing comptime work.
    // We need the data layout for ConstCastOnly == true
    // types to be the same, so all optionals of pointer types use x_ptr
    // instead of x_optional.
    ConstPtrSpecialNull,
};

enum ConstPtrMut {
    // The pointer points to memory that is known at compile time and immutable.
    ConstPtrMutComptimeConst,
    // This means that the pointer points to memory used by a comptime variable,
    // so attempting to write a non-compile-time known value is an error
    // But the underlying value is allowed to change at compile time.
    ConstPtrMutComptimeVar,
    // The pointer points to memory that is known only at runtime.
    // For example it may point to the initializer value of a variable.
    ConstPtrMutRuntimeVar,
    // The pointer points to memory for which it must be inferred whether the
    // value is comptime known or not.
    ConstPtrMutInfer,
};

struct ConstPtrValue {
    ConstPtrSpecial special;
    ConstPtrMut mut;

    union {
        struct {
            ConstExprValue *pointee;
        } ref;
        struct {
            ConstExprValue *array_val;
            size_t elem_index;
            // This helps us preserve the null byte when performing compile-time
            // concatenation on C strings.
            bool is_cstr;
        } base_array;
        struct {
            ConstExprValue *struct_val;
            size_t field_index;
        } base_struct;
        struct {
            ConstExprValue *err_union_val;
        } base_err_union_code;
        struct {
            ConstExprValue *err_union_val;
        } base_err_union_payload;
        struct {
            ConstExprValue *optional_val;
        } base_optional_payload;
        struct {
            uint64_t addr;
        } hard_coded_addr;
        struct {
            ZigFn *fn_entry;
        } fn;
    } data;
};

struct ConstErrValue {
    ConstExprValue *error_set;
    ConstExprValue *payload;
};

struct ConstBoundFnValue {
    ZigFn *fn;
    IrInstruction *first_arg;
};

struct ConstArgTuple {
    size_t start_index;
    size_t end_index;
};

enum ConstValSpecial {
    ConstValSpecialRuntime,
    ConstValSpecialStatic,
    ConstValSpecialUndef,
};

enum RuntimeHintErrorUnion {
    RuntimeHintErrorUnionUnknown,
    RuntimeHintErrorUnionError,
    RuntimeHintErrorUnionNonError,
};

enum RuntimeHintOptional {
    RuntimeHintOptionalUnknown,
    RuntimeHintOptionalNull, // TODO is this value even possible? if this is the case it might mean the const value is compile time known.
    RuntimeHintOptionalNonNull,
};

enum RuntimeHintPtr {
    RuntimeHintPtrUnknown,
    RuntimeHintPtrStack,
    RuntimeHintPtrNonStack,
};

enum RuntimeHintSliceId {
    RuntimeHintSliceIdUnknown,
    RuntimeHintSliceIdLen,
};

struct RuntimeHintSlice {
    enum RuntimeHintSliceId id;
    uint64_t len;
};

struct ConstGlobalRefs {
    LLVMValueRef llvm_value;
    LLVMValueRef llvm_global;
    uint32_t align;
};

struct ConstExprValue {
    ZigType *type;
    ConstValSpecial special;
    ConstParent parent;
    ConstGlobalRefs *global_refs;

    union {
        // populated if special == ConstValSpecialStatic
        BigInt x_bigint;
        BigFloat x_bigfloat;
        float16_t x_f16;
        float x_f32;
        double x_f64;
        float128_t x_f128;
        bool x_bool;
        ConstBoundFnValue x_bound_fn;
        ZigType *x_type;
        ConstExprValue *x_optional;
        ConstErrValue x_err_union;
        ErrorTableEntry *x_err_set;
        BigInt x_enum_tag;
        ConstStructValue x_struct;
        ConstUnionValue x_union;
        ConstArrayValue x_array;
        ConstPtrValue x_ptr;
        ConstArgTuple x_arg_tuple;
        Buf *x_enum_literal;

        // populated if special == ConstValSpecialRuntime
        RuntimeHintErrorUnion rh_error_union;
        RuntimeHintOptional rh_maybe;
        RuntimeHintPtr rh_ptr;
        RuntimeHintSlice rh_slice;
    } data;

    // uncomment these to find bugs. can't leave them uncommented because of a gcc-9 warning
    //ConstExprValue(const ConstExprValue &other) = delete; // plz zero initialize with {}
    //ConstExprValue& operator= (const ConstExprValue &other) = delete; // use copy_const_val
};

enum ReturnKnowledge {
    ReturnKnowledgeUnknown,
    ReturnKnowledgeKnownError,
    ReturnKnowledgeKnownNonError,
    ReturnKnowledgeKnownNull,
    ReturnKnowledgeKnownNonNull,
    ReturnKnowledgeSkipDefers,
};

enum VisibMod {
    VisibModPrivate,
    VisibModPub,
};

enum GlobalLinkageId {
    GlobalLinkageIdInternal,
    GlobalLinkageIdStrong,
    GlobalLinkageIdWeak,
    GlobalLinkageIdLinkOnce,
};

enum TldId {
    TldIdVar,
    TldIdFn,
    TldIdContainer,
    TldIdCompTime,
    TldIdUsingNamespace,
};

enum TldResolution {
    TldResolutionUnresolved,
    TldResolutionResolving,
    TldResolutionInvalid,
    TldResolutionOk,
};

struct Tld {
    TldId id;
    Buf *name;
    VisibMod visib_mod;
    AstNode *source_node;

    ZigType *import;
    Scope *parent_scope;
    TldResolution resolution;
};

struct TldVar {
    Tld base;

    ZigVar *var;
    Buf *extern_lib_name;
    Buf *section_name;
    bool analyzing_type; // flag to detect dependency loops
};

struct TldFn {
    Tld base;

    ZigFn *fn_entry;
    Buf *extern_lib_name;
};

struct TldContainer {
    Tld base;

    ScopeDecls *decls_scope;
    ZigType *type_entry;
};

struct TldCompTime {
    Tld base;
};

struct TldUsingNamespace {
    Tld base;

    ConstExprValue *using_namespace_value;
};

struct TypeEnumField {
    Buf *name;
    BigInt value;
    uint32_t decl_index;
    AstNode *decl_node;
};

struct TypeUnionField {
    Buf *name;
    TypeEnumField *enum_field;
    ZigType *type_entry;
    AstNode *decl_node;
    uint32_t gen_index;
};

enum NodeType {
    NodeTypeFnProto,
    NodeTypeFnDef,
    NodeTypeParamDecl,
    NodeTypeBlock,
    NodeTypeGroupedExpr,
    NodeTypeReturnExpr,
    NodeTypeDefer,
    NodeTypeVariableDeclaration,
    NodeTypeTestDecl,
    NodeTypeBinOpExpr,
    NodeTypeCatchExpr,
    NodeTypeFloatLiteral,
    NodeTypeIntLiteral,
    NodeTypeStringLiteral,
    NodeTypeCharLiteral,
    NodeTypeSymbol,
    NodeTypePrefixOpExpr,
    NodeTypePointerType,
    NodeTypeFnCallExpr,
    NodeTypeArrayAccessExpr,
    NodeTypeSliceExpr,
    NodeTypeFieldAccessExpr,
    NodeTypePtrDeref,
    NodeTypeUnwrapOptional,
    NodeTypeUsingNamespace,
    NodeTypeBoolLiteral,
    NodeTypeNullLiteral,
    NodeTypeUndefinedLiteral,
    NodeTypeUnreachable,
    NodeTypeIfBoolExpr,
    NodeTypeWhileExpr,
    NodeTypeForExpr,
    NodeTypeSwitchExpr,
    NodeTypeSwitchProng,
    NodeTypeSwitchRange,
    NodeTypeCompTime,
    NodeTypeBreak,
    NodeTypeContinue,
    NodeTypeAsmExpr,
    NodeTypeContainerDecl,
    NodeTypeStructField,
    NodeTypeContainerInitExpr,
    NodeTypeStructValueField,
    NodeTypeArrayType,
    NodeTypeInferredArrayType,
    NodeTypeErrorType,
    NodeTypeIfErrorExpr,
    NodeTypeIfOptional,
    NodeTypeErrorSetDecl,
    NodeTypeCancel,
    NodeTypeResume,
    NodeTypeAwaitExpr,
    NodeTypeSuspend,
    NodeTypePromiseType,
    NodeTypeEnumLiteral,
};

enum CallingConvention {
    CallingConventionUnspecified,
    CallingConventionC,
    CallingConventionCold,
    CallingConventionNaked,
    CallingConventionStdcall,
    CallingConventionAsync,
};

struct AstNodeFnProto {
    VisibMod visib_mod;
    Buf *name;
    ZigList<AstNode *> params;
    AstNode *return_type;
    Token *return_var_token;
    bool is_var_args;
    bool is_extern;
    bool is_export;
    bool is_inline;
    CallingConvention cc;
    AstNode *fn_def_node;
    // populated if this is an extern declaration
    Buf *lib_name;
    // populated if the "align A" is present
    AstNode *align_expr;
    // populated if the "section(S)" is present
    AstNode *section_expr;

    bool auto_err_set;
    AstNode *async_allocator_type;
};

struct AstNodeFnDef {
    AstNode *fn_proto;
    AstNode *body;
};

struct AstNodeParamDecl {
    Buf *name;
    AstNode *type;
    Token *var_token;
    bool is_noalias;
    bool is_inline;
    bool is_var_args;
};

struct AstNodeBlock {
    Buf *name;
    ZigList<AstNode *> statements;
};

enum ReturnKind {
    ReturnKindUnconditional,
    ReturnKindError,
};

struct AstNodeReturnExpr {
    ReturnKind kind;
    // might be null in case of return void;
    AstNode *expr;
};

struct AstNodeDefer {
    ReturnKind kind;
    AstNode *expr;

    // temporary data used in IR generation
    Scope *child_scope;
    Scope *expr_scope;
};

struct AstNodeVariableDeclaration {
    Buf *symbol;
    // one or both of type and expr will be non null
    AstNode *type;
    AstNode *expr;
    // populated if this is an extern declaration
    Buf *lib_name;
    // populated if the "align(A)" is present
    AstNode *align_expr;
    // populated if the "section(S)" is present
    AstNode *section_expr;
    Token *threadlocal_tok;

    VisibMod visib_mod;
    bool is_const;
    bool is_comptime;
    bool is_export;
    bool is_extern;
};

struct AstNodeTestDecl {
    Buf *name;

    AstNode *body;
};

enum BinOpType {
    BinOpTypeInvalid,
    BinOpTypeAssign,
    BinOpTypeAssignTimes,
    BinOpTypeAssignTimesWrap,
    BinOpTypeAssignDiv,
    BinOpTypeAssignMod,
    BinOpTypeAssignPlus,
    BinOpTypeAssignPlusWrap,
    BinOpTypeAssignMinus,
    BinOpTypeAssignMinusWrap,
    BinOpTypeAssignBitShiftLeft,
    BinOpTypeAssignBitShiftRight,
    BinOpTypeAssignBitAnd,
    BinOpTypeAssignBitXor,
    BinOpTypeAssignBitOr,
    BinOpTypeAssignMergeErrorSets,
    BinOpTypeBoolOr,
    BinOpTypeBoolAnd,
    BinOpTypeCmpEq,
    BinOpTypeCmpNotEq,
    BinOpTypeCmpLessThan,
    BinOpTypeCmpGreaterThan,
    BinOpTypeCmpLessOrEq,
    BinOpTypeCmpGreaterOrEq,
    BinOpTypeBinOr,
    BinOpTypeBinXor,
    BinOpTypeBinAnd,
    BinOpTypeBitShiftLeft,
    BinOpTypeBitShiftRight,
    BinOpTypeAdd,
    BinOpTypeAddWrap,
    BinOpTypeSub,
    BinOpTypeSubWrap,
    BinOpTypeMult,
    BinOpTypeMultWrap,
    BinOpTypeDiv,
    BinOpTypeMod,
    BinOpTypeUnwrapOptional,
    BinOpTypeArrayCat,
    BinOpTypeArrayMult,
    BinOpTypeErrorUnion,
    BinOpTypeMergeErrorSets,
};

struct AstNodeBinOpExpr {
    AstNode *op1;
    BinOpType bin_op;
    AstNode *op2;
};

struct AstNodeCatchExpr {
    AstNode *op1;
    AstNode *symbol; // can be null
    AstNode *op2;
};

struct AstNodeUnwrapOptional {
    AstNode *expr;
};

struct AstNodeFnCallExpr {
    AstNode *fn_ref_expr;
    ZigList<AstNode *> params;
    bool is_builtin;
    bool is_async;
    bool seen; // used by @compileLog
    AstNode *async_allocator;
};

struct AstNodeArrayAccessExpr {
    AstNode *array_ref_expr;
    AstNode *subscript;
};

struct AstNodeSliceExpr {
    AstNode *array_ref_expr;
    AstNode *start;
    AstNode *end;
};

struct AstNodeFieldAccessExpr {
    AstNode *struct_expr;
    Buf *field_name;
};

struct AstNodePtrDerefExpr {
    AstNode *target;
};

enum PrefixOp {
    PrefixOpInvalid,
    PrefixOpBoolNot,
    PrefixOpBinNot,
    PrefixOpNegation,
    PrefixOpNegationWrap,
    PrefixOpOptional,
    PrefixOpAddrOf,
};

struct AstNodePrefixOpExpr {
    PrefixOp prefix_op;
    AstNode *primary_expr;
};

struct AstNodePointerType {
    Token *star_token;
    AstNode *align_expr;
    BigInt *bit_offset_start;
    BigInt *host_int_bytes;
    AstNode *op_expr;
    Token *allow_zero_token;
    bool is_const;
    bool is_volatile;
};

struct AstNodeInferredArrayType {
    AstNode *child_type;
};

struct AstNodeArrayType {
    AstNode *size;
    AstNode *child_type;
    AstNode *align_expr;
    Token *allow_zero_token;
    bool is_const;
    bool is_volatile;
};

struct AstNodeUsingNamespace {
    VisibMod visib_mod;
    AstNode *expr;
};

struct AstNodeIfBoolExpr {
    AstNode *condition;
    AstNode *then_block;
    AstNode *else_node; // null, block node, or other if expr node
};

struct AstNodeTryExpr {
    Buf *var_symbol;
    bool var_is_ptr;
    AstNode *target_node;
    AstNode *then_node;
    AstNode *else_node;
    Buf *err_symbol;
};

struct AstNodeTestExpr {
    Buf *var_symbol;
    bool var_is_ptr;
    AstNode *target_node;
    AstNode *then_node;
    AstNode *else_node; // null, block node, or other if expr node
};

struct AstNodeWhileExpr {
    Buf *name;
    AstNode *condition;
    Buf *var_symbol;
    bool var_is_ptr;
    AstNode *continue_expr;
    AstNode *body;
    AstNode *else_node;
    Buf *err_symbol;
    bool is_inline;
};

struct AstNodeForExpr {
    Buf *name;
    AstNode *array_expr;
    AstNode *elem_node; // always a symbol
    AstNode *index_node; // always a symbol, might be null
    AstNode *body;
    AstNode *else_node; // can be null
    bool elem_is_ptr;
    bool is_inline;
};

struct AstNodeSwitchExpr {
    AstNode *expr;
    ZigList<AstNode *> prongs;
};

struct AstNodeSwitchProng {
    ZigList<AstNode *> items;
    AstNode *var_symbol;
    AstNode *expr;
    bool var_is_ptr;
    bool any_items_are_range;
};

struct AstNodeSwitchRange {
    AstNode *start;
    AstNode *end;
};

struct AstNodeCompTime {
    AstNode *expr;
};

struct AsmOutput {
    Buf *asm_symbolic_name;
    Buf *constraint;
    Buf *variable_name;
    AstNode *return_type; // null unless "=r" and return
};

struct AsmInput {
    Buf *asm_symbolic_name;
    Buf *constraint;
    AstNode *expr;
};

struct SrcPos {
    size_t line;
    size_t column;
};

enum AsmTokenId {
    AsmTokenIdTemplate,
    AsmTokenIdPercent,
    AsmTokenIdVar,
    AsmTokenIdUniqueId,
};

struct AsmToken {
    enum AsmTokenId id;
    size_t start;
    size_t end;
};

struct AstNodeAsmExpr {
    Token *volatile_token;
    Token *asm_template;
    ZigList<AsmOutput*> output_list;
    ZigList<AsmInput*> input_list;
    ZigList<Buf*> clobber_list;
};

enum ContainerKind {
    ContainerKindStruct,
    ContainerKindEnum,
    ContainerKindUnion,
};

enum ContainerLayout {
    ContainerLayoutAuto,
    ContainerLayoutExtern,
    ContainerLayoutPacked,
};

struct AstNodeContainerDecl {
    ContainerKind kind;
    ZigList<AstNode *> fields;
    ZigList<AstNode *> decls;
    ContainerLayout layout;
    AstNode *init_arg_expr; // enum(T), struct(endianness), or union(T), or union(enum(T))
    bool auto_enum, is_root; // union(enum)
};

struct AstNodeErrorSetDecl {
    ZigList<AstNode *> decls;
};

struct AstNodeStructField {
    VisibMod visib_mod;
    Buf *name;
    AstNode *type;
    AstNode *value;
};

struct AstNodeStringLiteral {
    Buf *buf;
    bool c;
};

struct AstNodeCharLiteral {
    uint32_t value;
};

struct AstNodeFloatLiteral {
    BigFloat *bigfloat;

    // overflow is true if when parsing the number, we discovered it would not
    // fit without losing data in a double
    bool overflow;
};

struct AstNodeIntLiteral {
    BigInt *bigint;
};

struct AstNodeStructValueField {
    Buf *name;
    AstNode *expr;
};

enum ContainerInitKind {
    ContainerInitKindStruct,
    ContainerInitKindArray,
};

struct AstNodeContainerInitExpr {
    AstNode *type;
    ZigList<AstNode *> entries;
    ContainerInitKind kind;
};

struct AstNodeNullLiteral {
};

struct AstNodeUndefinedLiteral {
};

struct AstNodeThisLiteral {
};

struct AstNodeSymbolExpr {
    Buf *symbol;
};

struct AstNodeBoolLiteral {
    bool value;
};

struct AstNodeBreakExpr {
    Buf *name;
    AstNode *expr; // may be null
};

struct AstNodeCancelExpr {
    AstNode *expr;
};

struct AstNodeResumeExpr {
    AstNode *expr;
};

struct AstNodeContinueExpr {
    Buf *name;
};

struct AstNodeUnreachableExpr {
};


struct AstNodeErrorType {
};

struct AstNodeAwaitExpr {
    AstNode *expr;
};

struct AstNodeSuspend {
    AstNode *block;
};

struct AstNodePromiseType {
    AstNode *payload_type; // can be NULL
};

struct AstNodeEnumLiteral {
    Token *period;
    Token *identifier;
};

struct AstNode {
    enum NodeType type;
    size_t line;
    size_t column;
    ZigType *owner;
    union {
        AstNodeFnDef fn_def;
        AstNodeFnProto fn_proto;
        AstNodeParamDecl param_decl;
        AstNodeBlock block;
        AstNode * grouped_expr;
        AstNodeReturnExpr return_expr;
        AstNodeDefer defer;
        AstNodeVariableDeclaration variable_declaration;
        AstNodeTestDecl test_decl;
        AstNodeBinOpExpr bin_op_expr;
        AstNodeCatchExpr unwrap_err_expr;
        AstNodeUnwrapOptional unwrap_optional;
        AstNodePrefixOpExpr prefix_op_expr;
        AstNodePointerType pointer_type;
        AstNodeFnCallExpr fn_call_expr;
        AstNodeArrayAccessExpr array_access_expr;
        AstNodeSliceExpr slice_expr;
        AstNodeUsingNamespace using_namespace;
        AstNodeIfBoolExpr if_bool_expr;
        AstNodeTryExpr if_err_expr;
        AstNodeTestExpr test_expr;
        AstNodeWhileExpr while_expr;
        AstNodeForExpr for_expr;
        AstNodeSwitchExpr switch_expr;
        AstNodeSwitchProng switch_prong;
        AstNodeSwitchRange switch_range;
        AstNodeCompTime comptime_expr;
        AstNodeAsmExpr asm_expr;
        AstNodeFieldAccessExpr field_access_expr;
        AstNodePtrDerefExpr ptr_deref_expr;
        AstNodeContainerDecl container_decl;
        AstNodeStructField struct_field;
        AstNodeStringLiteral string_literal;
        AstNodeCharLiteral char_literal;
        AstNodeFloatLiteral float_literal;
        AstNodeIntLiteral int_literal;
        AstNodeContainerInitExpr container_init_expr;
        AstNodeStructValueField struct_val_field;
        AstNodeNullLiteral null_literal;
        AstNodeUndefinedLiteral undefined_literal;
        AstNodeThisLiteral this_literal;
        AstNodeSymbolExpr symbol_expr;
        AstNodeBoolLiteral bool_literal;
        AstNodeBreakExpr break_expr;
        AstNodeContinueExpr continue_expr;
        AstNodeUnreachableExpr unreachable_expr;
        AstNodeArrayType array_type;
        AstNodeInferredArrayType inferred_array_type;
        AstNodeErrorType error_type;
        AstNodeErrorSetDecl err_set_decl;
        AstNodeCancelExpr cancel_expr;
        AstNodeResumeExpr resume_expr;
        AstNodeAwaitExpr await_expr;
        AstNodeSuspend suspend;
        AstNodePromiseType promise_type;
        AstNodeEnumLiteral enum_literal;
    } data;
};

// this struct is allocated with allocate_nonzero
struct FnTypeParamInfo {
    bool is_noalias;
    ZigType *type;
};

struct GenericFnTypeId {
    CodeGen *codegen;
    ZigFn *fn_entry;
    ConstExprValue *params;
    size_t param_count;
};

uint32_t generic_fn_type_id_hash(GenericFnTypeId *id);
bool generic_fn_type_id_eql(GenericFnTypeId *a, GenericFnTypeId *b);

struct FnTypeId {
    ZigType *return_type;
    FnTypeParamInfo *param_info;
    size_t param_count;
    size_t next_param_index;
    bool is_var_args;
    CallingConvention cc;
    uint32_t alignment;
    ZigType *async_allocator_type;
};

uint32_t fn_type_id_hash(FnTypeId*);
bool fn_type_id_eql(FnTypeId *a, FnTypeId *b);

enum PtrLen {
    PtrLenUnknown,
    PtrLenSingle,
    PtrLenC,
};

struct ZigTypePointer {
    ZigType *child_type;
    ZigType *slice_parent;
    PtrLen ptr_len;
    uint32_t explicit_alignment; // 0 means use ABI alignment
    uint32_t bit_offset_in_host;
    uint32_t host_int_bytes; // size of host integer. 0 means no host integer; this field is aligned
    bool is_const;
    bool is_volatile;
    bool allow_zero;
};

struct ZigTypeInt {
    uint32_t bit_count;
    bool is_signed;
};

struct ZigTypeFloat {
    size_t bit_count;
};

struct ZigTypeArray {
    ZigType *child_type;
    uint64_t len;
};

struct TypeStructField {
    Buf *name;
    ZigType *type_entry;
    size_t src_index;
    size_t gen_index;
    size_t offset; // byte offset from beginning of struct
    AstNode *decl_node;
    ConstExprValue *init_val; // null and then memoized
    uint32_t bit_offset_in_host; // offset from the memory at gen_index
    uint32_t host_int_bytes; // size of host integer
};

enum ResolveStatus {
    ResolveStatusUnstarted,
    ResolveStatusInvalid,
    ResolveStatusZeroBitsKnown,
    ResolveStatusAlignmentKnown,
    ResolveStatusSizeKnown,
    ResolveStatusLLVMFwdDecl,
    ResolveStatusLLVMFull,
};

struct ZigPackage {
    Buf root_src_dir;
    Buf root_src_path; // relative to root_src_dir
    Buf pkg_path; // a.b.c.d which follows the package dependency chain from the root package

    // reminder: hash tables must be initialized before use
    HashMap<Buf *, ZigPackage *, buf_hash, buf_eql_buf> package_table;

    bool added_to_cache;
};

// Stuff that only applies to a struct which is the implicit root struct of a file
struct RootStruct {
    ZigPackage *package;
    Buf *path; // relative to root_package->root_src_dir
    ZigList<size_t> *line_offsets;
    Buf *source_code;
    ZigLLVMDIFile *di_file;
};

struct ZigTypeStruct {
    AstNode *decl_node;
    TypeStructField *fields;
    ScopeDecls *decls_scope;
    HashMap<Buf *, TypeStructField *, buf_hash, buf_eql_buf> fields_by_name;
    RootStruct *root_struct;
    uint32_t *host_int_bytes; // available for packed structs, indexed by gen_index

    uint32_t src_field_count;
    uint32_t gen_field_count;

    ContainerLayout layout;
    ResolveStatus resolve_status;

    bool is_slice;
    bool resolve_loop_flag; // set this flag temporarily to detect infinite loops
    bool reported_infinite_err;
    // whether any of the fields require comptime
    // known after ResolveStatusZeroBitsKnown
    bool requires_comptime;
};

struct ZigTypeOptional {
    ZigType *child_type;
};

struct ZigTypeErrorUnion {
    ZigType *err_set_type;
    ZigType *payload_type;
};

struct ZigTypeErrorSet {
    uint32_t err_count;
    ErrorTableEntry **errors;
    ZigFn *infer_fn;
};

struct ZigTypeEnum {
    AstNode *decl_node;
    ContainerLayout layout;
    uint32_t src_field_count;
    TypeEnumField *fields;
    bool is_invalid; // true if any fields are invalid
    ZigType *tag_int_type;

    ScopeDecls *decls_scope;

    // set this flag temporarily to detect infinite loops
    bool embedded_in_current;
    bool reported_infinite_err;
    // whether we've finished resolving it
    bool complete;

    bool zero_bits_loop_flag;
    bool zero_bits_known;

    LLVMValueRef name_function;

    HashMap<Buf *, TypeEnumField *, buf_hash, buf_eql_buf> fields_by_name;
};

uint32_t type_ptr_hash(const ZigType *ptr);
bool type_ptr_eql(const ZigType *a, const ZigType *b);

struct ZigTypeUnion {
    AstNode *decl_node;
    TypeUnionField *fields;
    ScopeDecls *decls_scope;
    HashMap<Buf *, TypeUnionField *, buf_hash, buf_eql_buf> fields_by_name;
    ZigType *tag_type; // always an enum or null
    LLVMTypeRef union_llvm_type;
    ZigType *most_aligned_union_member;
    size_t gen_union_index;
    size_t gen_tag_index;
    size_t union_abi_size;

    uint32_t src_field_count;
    uint32_t gen_field_count;

    ContainerLayout layout;
    ResolveStatus resolve_status;

    bool have_explicit_tag_type;
    bool resolve_loop_flag; // set this flag temporarily to detect infinite loops
    bool reported_infinite_err;
    // whether any of the fields require comptime
    // the value is not valid until zero_bits_known == true
    bool requires_comptime;
};

struct FnGenParamInfo {
    size_t src_index;
    size_t gen_index;
    bool is_byval;
    ZigType *type;
};

struct ZigTypeFn {
    FnTypeId fn_type_id;
    bool is_generic;
    ZigType *gen_return_type;
    size_t gen_param_count;
    FnGenParamInfo *gen_param_info;

    LLVMTypeRef raw_type_ref;
    ZigLLVMDIType *raw_di_type;

    ZigType *bound_fn_parent;
};

struct ZigTypeBoundFn {
    ZigType *fn_type;
};

struct ZigTypePromise {
    // null if `promise` instead of `promise->T`
    ZigType *result_type;
};

struct ZigTypeVector {
    // The type must be a pointer, integer, or float
    ZigType *elem_type;
    uint32_t len;
};

enum ZigTypeId {
    ZigTypeIdInvalid,
    ZigTypeIdMetaType,
    ZigTypeIdVoid,
    ZigTypeIdBool,
    ZigTypeIdUnreachable,
    ZigTypeIdInt,
    ZigTypeIdFloat,
    ZigTypeIdPointer,
    ZigTypeIdArray,
    ZigTypeIdStruct,
    ZigTypeIdComptimeFloat,
    ZigTypeIdComptimeInt,
    ZigTypeIdUndefined,
    ZigTypeIdNull,
    ZigTypeIdOptional,
    ZigTypeIdErrorUnion,
    ZigTypeIdErrorSet,
    ZigTypeIdEnum,
    ZigTypeIdUnion,
    ZigTypeIdFn,
    ZigTypeIdBoundFn,
    ZigTypeIdArgTuple,
    ZigTypeIdOpaque,
    ZigTypeIdPromise,
    ZigTypeIdVector,
    ZigTypeIdEnumLiteral,
};

enum OnePossibleValue {
    OnePossibleValueInvalid,
    OnePossibleValueNo,
    OnePossibleValueYes,
};

struct ZigTypeOpaque {
    Buf *bare_name;
};

struct ZigType {
    ZigTypeId id;
    Buf name;

    // These are not supposed to be accessed directly. They're
    // null during semantic analysis, memoized with get_llvm_type
    // and get_llvm_di_type
    LLVMTypeRef llvm_type;
    ZigLLVMDIType *llvm_di_type;

    union {
        ZigTypePointer pointer;
        ZigTypeInt integral;
        ZigTypeFloat floating;
        ZigTypeArray array;
        ZigTypeStruct structure;
        ZigTypeOptional maybe;
        ZigTypeErrorUnion error_union;
        ZigTypeErrorSet error_set;
        ZigTypeEnum enumeration;
        ZigTypeUnion unionation;
        ZigTypeFn fn;
        ZigTypeBoundFn bound_fn;
        ZigTypePromise promise;
        ZigTypeVector vector;
        ZigTypeOpaque opaque;
    } data;

    // use these fields to make sure we don't duplicate type table entries for the same type
    ZigType *pointer_parent[2]; // [0 - mut, 1 - const]
    ZigType *optional_parent;
    ZigType *promise_parent;
    ZigType *promise_frame_parent;
    // If we generate a constant name value for this type, we memoize it here.
    // The type of this is array
    ConstExprValue *cached_const_name_val;

    OnePossibleValue one_possible_value;
    // Known after ResolveStatusAlignmentKnown.
    uint32_t abi_align;
    // The offset in bytes between consecutive array elements of this type. Known
    // after ResolveStatusSizeKnown.
    size_t abi_size;
    // Number of bits of information in this type. Known after ResolveStatusSizeKnown.
    size_t size_in_bits;

    bool gen_h_loop_flag;
};

enum FnAnalState {
    FnAnalStateReady,
    FnAnalStateProbing,
    FnAnalStateComplete,
    FnAnalStateInvalid,
};

enum FnInline {
    FnInlineAuto,
    FnInlineAlways,
    FnInlineNever,
};

struct GlobalExport {
    Buf name;
    GlobalLinkageId linkage;
};

struct ZigFn {
    CodeGen *codegen;
    LLVMValueRef llvm_value;
    const char *llvm_name;
    AstNode *proto_node;
    AstNode *body_node;
    ScopeFnDef *fndef_scope; // parent should be the top level decls or container decls
    Scope *child_scope; // parent is scope for last parameter
    ScopeBlock *def_scope; // parent is child_scope
    Buf symbol_name;
    ZigType *type_entry; // function type
    // in the case of normal functions this is the implicit return type
    // in the case of async functions this is the implicit return type according to the
    // zig source code, not according to zig ir
    ZigType *src_implicit_return_type;
    IrExecutable ir_executable;
    IrExecutable analyzed_executable;
    size_t prealloc_bbc;
    size_t prealloc_backward_branch_quota;
    AstNode **param_source_nodes;
    Buf **param_names;

    AstNode *fn_no_inline_set_node;
    AstNode *fn_static_eval_set_node;

    ZigList<IrInstructionAllocaGen *> alloca_gen_list;
    ZigList<ZigVar *> variable_list;

    Buf *section_name;
    AstNode *set_alignstack_node;

    AstNode *set_cold_node;

    ZigList<GlobalExport> export_list;

    LLVMValueRef valgrind_client_request_array;

    FnInline fn_inline;
    FnAnalState anal_state;

    uint32_t align_bytes;
    uint32_t alignstack_value;

    bool calls_or_awaits_errorable_fn;
    bool is_cold;
    bool is_test;
};

uint32_t fn_table_entry_hash(ZigFn*);
bool fn_table_entry_eql(ZigFn *a, ZigFn *b);

enum BuiltinFnId {
    BuiltinFnIdInvalid,
    BuiltinFnIdMemcpy,
    BuiltinFnIdMemset,
    BuiltinFnIdSizeof,
    BuiltinFnIdAlignOf,
    BuiltinFnIdMemberCount,
    BuiltinFnIdMemberType,
    BuiltinFnIdMemberName,
    BuiltinFnIdField,
    BuiltinFnIdTypeInfo,
    BuiltinFnIdHasField,
    BuiltinFnIdTypeof,
    BuiltinFnIdAddWithOverflow,
    BuiltinFnIdSubWithOverflow,
    BuiltinFnIdMulWithOverflow,
    BuiltinFnIdShlWithOverflow,
    BuiltinFnIdMulAdd,
    BuiltinFnIdCInclude,
    BuiltinFnIdCDefine,
    BuiltinFnIdCUndef,
    BuiltinFnIdCompileErr,
    BuiltinFnIdCompileLog,
    BuiltinFnIdCtz,
    BuiltinFnIdClz,
    BuiltinFnIdPopCount,
    BuiltinFnIdBswap,
    BuiltinFnIdBitReverse,
    BuiltinFnIdImport,
    BuiltinFnIdCImport,
    BuiltinFnIdErrName,
    BuiltinFnIdBreakpoint,
    BuiltinFnIdReturnAddress,
    BuiltinFnIdFrameAddress,
    BuiltinFnIdHandle,
    BuiltinFnIdEmbedFile,
    BuiltinFnIdCmpxchgWeak,
    BuiltinFnIdCmpxchgStrong,
    BuiltinFnIdFence,
    BuiltinFnIdDivExact,
    BuiltinFnIdDivTrunc,
    BuiltinFnIdDivFloor,
    BuiltinFnIdRem,
    BuiltinFnIdMod,
    BuiltinFnIdSqrt,
    BuiltinFnIdSin,
    BuiltinFnIdCos,
    BuiltinFnIdExp,
    BuiltinFnIdExp2,
    BuiltinFnIdLn,
    BuiltinFnIdLog2,
    BuiltinFnIdLog10,
    BuiltinFnIdFabs,
    BuiltinFnIdFloor,
    BuiltinFnIdCeil,
    BuiltinFnIdTrunc,
    BuiltinFnIdNearbyInt,
    BuiltinFnIdRound,
    BuiltinFnIdTruncate,
    BuiltinFnIdIntCast,
    BuiltinFnIdFloatCast,
    BuiltinFnIdErrSetCast,
    BuiltinFnIdToBytes,
    BuiltinFnIdFromBytes,
    BuiltinFnIdIntToFloat,
    BuiltinFnIdFloatToInt,
    BuiltinFnIdBoolToInt,
    BuiltinFnIdErrToInt,
    BuiltinFnIdIntToErr,
    BuiltinFnIdEnumToInt,
    BuiltinFnIdIntToEnum,
    BuiltinFnIdIntType,
    BuiltinFnIdVectorType,
    BuiltinFnIdShuffle,
    BuiltinFnIdGather,
    BuiltinFnIdScatter,
    BuiltinFnIdSplat,
    BuiltinFnIdSetCold,
    BuiltinFnIdSetRuntimeSafety,
    BuiltinFnIdSetFloatMode,
    BuiltinFnIdTypeName,
    BuiltinFnIdPanic,
    BuiltinFnIdPtrCast,
    BuiltinFnIdBitCast,
    BuiltinFnIdIntToPtr,
    BuiltinFnIdPtrToInt,
    BuiltinFnIdTagName,
    BuiltinFnIdTagType,
    BuiltinFnIdFieldParentPtr,
    BuiltinFnIdByteOffsetOf,
    BuiltinFnIdBitOffsetOf,
    BuiltinFnIdInlineCall,
    BuiltinFnIdNoInlineCall,
    BuiltinFnIdNewStackCall,
    BuiltinFnIdTypeId,
    BuiltinFnIdShlExact,
    BuiltinFnIdShrExact,
    BuiltinFnIdSetEvalBranchQuota,
    BuiltinFnIdAlignCast,
    BuiltinFnIdOpaqueType,
    BuiltinFnIdThis,
    BuiltinFnIdSetAlignStack,
    BuiltinFnIdArgType,
    BuiltinFnIdExport,
    BuiltinFnIdErrorReturnTrace,
    BuiltinFnIdAtomicRmw,
    BuiltinFnIdAtomicLoad,
    BuiltinFnIdHasDecl,
    BuiltinFnIdUnionInit,
};

struct BuiltinFnEntry {
    BuiltinFnId id;
    Buf name;
    size_t param_count;
};

enum PanicMsgId {
    PanicMsgIdUnreachable,
    PanicMsgIdBoundsCheckFailure,
    PanicMsgIdCastNegativeToUnsigned,
    PanicMsgIdCastTruncatedData,
    PanicMsgIdIntegerOverflow,
    PanicMsgIdShlOverflowedBits,
    PanicMsgIdShrOverflowedBits,
    PanicMsgIdDivisionByZero,
    PanicMsgIdRemainderDivisionByZero,
    PanicMsgIdExactDivisionRemainder,
    PanicMsgIdSliceWidenRemainder,
    PanicMsgIdUnwrapOptionalFail,
    PanicMsgIdInvalidErrorCode,
    PanicMsgIdIncorrectAlignment,
    PanicMsgIdBadUnionField,
    PanicMsgIdBadEnumValue,
    PanicMsgIdFloatToInt,
    PanicMsgIdPtrCastNull,

    PanicMsgIdCount,
};

uint32_t fn_eval_hash(Scope*);
bool fn_eval_eql(Scope *a, Scope *b);

struct TypeId {
    ZigTypeId id;

    union {
        struct {
            ZigType *child_type;
            PtrLen ptr_len;
            uint32_t alignment;
            uint32_t bit_offset_in_host;
            uint32_t host_int_bytes;
            bool is_const;
            bool is_volatile;
            bool allow_zero;
        } pointer;
        struct {
            ZigType *child_type;
            uint64_t size;
        } array;
        struct {
            bool is_signed;
            uint32_t bit_count;
        } integer;
        struct {
            ZigType *err_set_type;
            ZigType *payload_type;
        } error_union;
        struct {
            ZigType *elem_type;
            uint32_t len;
        } vector;
    } data;
};

uint32_t type_id_hash(TypeId);
bool type_id_eql(TypeId a, TypeId b);

enum ZigLLVMFnId {
    ZigLLVMFnIdCtz,
    ZigLLVMFnIdClz,
    ZigLLVMFnIdPopCount,
    ZigLLVMFnIdOverflowArithmetic,
    ZigLLVMFnIdMaskedVector,
    ZigLLVMFnIdFMA,
    ZigLLVMFnIdFloatOp,
    ZigLLVMFnIdBswap,
    ZigLLVMFnIdBitReverse,
};

// There are a bunch of places in code that rely on these values being in
// exactly this order.
enum AddSubMul {
    AddSubMulAdd = 0,
    AddSubMulSub = 1,
    AddSubMulMul = 2,
};

struct ZigLLVMFnKey {
    ZigLLVMFnId id;

    union {
        struct {
            uint32_t bit_count;
        } ctz;
        struct {
            uint32_t bit_count;
        } clz;
        struct {
            uint32_t bit_count;
        } pop_count;
        struct {
            BuiltinFnId op;
            uint32_t bit_count;
            uint32_t vector_len; // 0 means not a vector
        } floating;
        struct {
            AddSubMul add_sub_mul;
            uint32_t bit_count;
            uint32_t vector_len; // 0 means not a vector
            bool is_signed;
        } overflow_arithmetic;
        struct {
            uint32_t bit_count;
            uint32_t vector_len; // 0 means not a vector
        } bswap;
        struct {
            uint32_t bit_count;
        } bit_reverse;
        struct {
            BuiltinFnId op;
            uint32_t bit_count;
            bool is_float;
            bool is_pointer;
            uint32_t vector_len;
        } masked_vector;
    } data;
};

uint32_t zig_llvm_fn_key_hash(ZigLLVMFnKey);
bool zig_llvm_fn_key_eql(ZigLLVMFnKey a, ZigLLVMFnKey b);

struct TimeEvent {
    double time;
    const char *name;
};

enum BuildMode {
    BuildModeDebug,
    BuildModeFastRelease,
    BuildModeSafeRelease,
    BuildModeSmallRelease,
};

enum EmitFileType {
    EmitFileTypeBinary,
    EmitFileTypeAssembly,
    EmitFileTypeLLVMIr,
};

struct LinkLib {
    Buf *name;
    Buf *path;
    ZigList<Buf *> symbols; // the list of symbols that we depend on from this lib
    bool provided_explicitly;
};

enum ValgrindSupport {
    ValgrindSupportAuto,
    ValgrindSupportDisabled,
    ValgrindSupportEnabled,
};

enum WantPIC {
    WantPICAuto,
    WantPICDisabled,
    WantPICEnabled,
};

enum WantStackCheck {
    WantStackCheckAuto,
    WantStackCheckDisabled,
    WantStackCheckEnabled,
};

struct CFile {
    ZigList<const char *> args;
    const char *source_path;
};

// When adding fields, check if they should be added to the hash computation in build_with_cache
struct CodeGen {
    //////////////////////////// Runtime State
    LLVMModuleRef module;
    ZigList<ErrorMsg*> errors;
    LLVMBuilderRef builder;
    ZigLLVMDIBuilder *dbuilder;
    ZigLLVMDICompileUnit *compile_unit;
    ZigLLVMDIFile *compile_unit_file;
    LinkLib *libc_link_lib;
    LLVMTargetDataRef target_data_ref;
    LLVMTargetMachineRef target_machine;
    ZigLLVMDIFile *dummy_di_file;
    LLVMValueRef cur_ret_ptr;
    LLVMValueRef cur_fn_val;
    LLVMValueRef cur_err_ret_trace_val_arg;
    LLVMValueRef cur_err_ret_trace_val_stack;
    LLVMValueRef memcpy_fn_val;
    LLVMValueRef memset_fn_val;
    LLVMValueRef trap_fn_val;
    LLVMValueRef return_address_fn_val;
    LLVMValueRef frame_address_fn_val;
    LLVMValueRef coro_destroy_fn_val;
    LLVMValueRef coro_id_fn_val;
    LLVMValueRef coro_alloc_fn_val;
    LLVMValueRef coro_size_fn_val;
    LLVMValueRef coro_begin_fn_val;
    LLVMValueRef coro_suspend_fn_val;
    LLVMValueRef coro_end_fn_val;
    LLVMValueRef coro_free_fn_val;
    LLVMValueRef coro_resume_fn_val;
    LLVMValueRef coro_save_fn_val;
    LLVMValueRef coro_promise_fn_val;
    LLVMValueRef coro_alloc_helper_fn_val;
    LLVMValueRef coro_frame_fn_val;
    LLVMValueRef merge_err_ret_traces_fn_val;
    LLVMValueRef add_error_return_trace_addr_fn_val;
    LLVMValueRef stacksave_fn_val;
    LLVMValueRef stackrestore_fn_val;
    LLVMValueRef write_register_fn_val;
    LLVMValueRef sp_md_node;
    LLVMValueRef err_name_table;
    LLVMValueRef safety_crash_err_fn;
    LLVMValueRef return_err_fn;

    // reminder: hash tables must be initialized before use
    HashMap<Buf *, ZigType *, buf_hash, buf_eql_buf> import_table;
    HashMap<Buf *, BuiltinFnEntry *, buf_hash, buf_eql_buf> builtin_fn_table;
    HashMap<Buf *, ZigType *, buf_hash, buf_eql_buf> primitive_type_table;
    HashMap<TypeId, ZigType *, type_id_hash, type_id_eql> type_table;
    HashMap<FnTypeId *, ZigType *, fn_type_id_hash, fn_type_id_eql> fn_type_table;
    HashMap<Buf *, ErrorTableEntry *, buf_hash, buf_eql_buf> error_table;
    HashMap<GenericFnTypeId *, ZigFn *, generic_fn_type_id_hash, generic_fn_type_id_eql> generic_table;
    HashMap<Scope *, ConstExprValue *, fn_eval_hash, fn_eval_eql> memoized_fn_eval_table;
    HashMap<ZigLLVMFnKey, LLVMValueRef, zig_llvm_fn_key_hash, zig_llvm_fn_key_eql> llvm_fn_table;
    HashMap<Buf *, Tld *, buf_hash, buf_eql_buf> exported_symbol_names;
    HashMap<Buf *, Tld *, buf_hash, buf_eql_buf> external_prototypes;
    HashMap<Buf *, ConstExprValue *, buf_hash, buf_eql_buf> string_literals_table;
    HashMap<const ZigType *, ConstExprValue *, type_ptr_hash, type_ptr_eql> type_info_cache;

    ZigList<Tld *> resolve_queue;
    size_t resolve_queue_index;
    ZigList<TimeEvent> timing_events;
    ZigList<AstNode *> tld_ref_source_node_stack;
    ZigList<ZigFn *> inline_fns;
    ZigList<ZigFn *> test_fns;
    ZigList<ErrorTableEntry *> errors_by_index;
    ZigList<CacheHash *> caches_to_release;
    size_t largest_err_name_len;

    ZigPackage *std_package;
    ZigPackage *panic_package;
    ZigPackage *test_runner_package;
    ZigPackage *compile_var_package;
    ZigType *compile_var_import;
    ZigType *root_import;
    ZigType *start_import;
    ZigType *test_runner_import;

    struct {
        ZigType *entry_bool;
        ZigType *entry_c_int[CIntTypeCount];
        ZigType *entry_c_longdouble;
        ZigType *entry_c_void;
        ZigType *entry_u8;
        ZigType *entry_u16;
        ZigType *entry_u32;
        ZigType *entry_u29;
        ZigType *entry_u64;
        ZigType *entry_i8;
        ZigType *entry_i32;
        ZigType *entry_i64;
        ZigType *entry_isize;
        ZigType *entry_usize;
        ZigType *entry_f16;
        ZigType *entry_f32;
        ZigType *entry_f64;
        ZigType *entry_f128;
        ZigType *entry_void;
        ZigType *entry_unreachable;
        ZigType *entry_type;
        ZigType *entry_invalid;
        ZigType *entry_block;
        ZigType *entry_num_lit_int;
        ZigType *entry_num_lit_float;
        ZigType *entry_undef;
        ZigType *entry_null;
        ZigType *entry_var;
        ZigType *entry_global_error_set;
        ZigType *entry_arg_tuple;
        ZigType *entry_promise;
        ZigType *entry_enum_literal;
    } builtin_types;
    ZigType *align_amt_type;
    ZigType *stack_trace_type;
    ZigType *ptr_to_stack_trace_type;
    ZigType *err_tag_type;
    ZigType *test_fn_type;

    Buf llvm_triple_str;
    Buf global_asm;
    Buf output_file_path;
    Buf o_file_output_path;
    Buf *cache_dir;
    // As an input parameter, mutually exclusive with enable_cache. But it gets
    // populated in codegen_build_and_link.
    Buf *output_dir;
    Buf **libc_include_dir_list;
    size_t libc_include_dir_len;

    Buf *zig_c_headers_dir; // Cannot be overridden; derived from zig_lib_dir.
    Buf *zig_std_special_dir; // Cannot be overridden; derived from zig_lib_dir.

    IrInstruction *invalid_instruction;
    IrInstruction *unreach_instruction;

    ConstExprValue const_void_val;
    ConstExprValue panic_msg_vals[PanicMsgIdCount];

    // The function definitions this module includes.
    ZigList<ZigFn *> fn_defs;
    size_t fn_defs_index;
    ZigList<TldVar *> global_vars;

    ZigFn *cur_fn;
    ZigFn *main_fn;
    ZigFn *panic_fn;
    TldFn *panic_tld_fn;
    AstNode *root_export_decl;

    WantPIC want_pic;
    WantStackCheck want_stack_check;
    CacheHash cache_hash;
    ErrColor err_color;
    uint32_t next_unresolved_index;
    unsigned pointer_size_bytes;
    uint32_t target_os_index;
    uint32_t target_arch_index;
    uint32_t target_sub_arch_index;
    uint32_t target_abi_index;
    uint32_t target_oformat_index;
    bool is_big_endian;
    bool have_pub_main;
    bool have_c_main;
    bool have_winmain;
    bool have_winmain_crt_startup;
    bool have_dllmain_crt_startup;
    bool have_pub_panic;
    bool have_err_ret_tracing;
    bool c_want_stdint;
    bool c_want_stdbool;
    bool verbose_tokenize;
    bool verbose_ast;
    bool verbose_link;
    bool verbose_ir;
    bool verbose_llvm_ir;
    bool verbose_cimport;
    bool verbose_cc;
    bool error_during_imports;
    bool generate_error_name_table;
    bool enable_cache; // mutually exclusive with output_dir
    bool enable_time_report;
    bool system_linker_hack;
    bool reported_bad_link_libc_error;
    bool is_dynamic; // shared library rather than static library. dynamic musl rather than static musl.

    //////////////////////////// Participates in Input Parameter Cache Hash
    /////// Note: there is a separate cache hash for builtin.zig, when adding fields,
    ///////       consider if they need to go into both.
    ZigList<LinkLib *> link_libs_list;
    // add -framework [name] args to linker
    ZigList<Buf *> darwin_frameworks;
    // add -rpath [name] args to linker
    ZigList<Buf *> rpath_list;
    ZigList<Buf *> forbidden_libs;
    ZigList<Buf *> link_objects;
    ZigList<Buf *> assembly_files;
    ZigList<CFile *> c_source_files;
    ZigList<const char *> lib_dirs;

    ZigLibCInstallation *libc;

    size_t version_major;
    size_t version_minor;
    size_t version_patch;
    const char *linker_script;

    EmitFileType emit_file_type;
    BuildMode build_mode;
    OutType out_type;
    const ZigTarget *zig_target;
    TargetSubsystem subsystem; // careful using this directly; see detect_subsystem
    ValgrindSupport valgrind_support;
    bool strip_debug_symbols;
    bool is_test_build;
    bool is_single_threaded;
    bool want_single_threaded;
    bool linker_rdynamic;
    bool each_lib_rpath;
    bool is_dummy_so;
    bool disable_gen_h;
    bool bundle_compiler_rt;
    bool have_pic;
    bool have_dynamic_link; // this is whether the final thing will be dynamically linked. see also is_dynamic
    bool have_stack_probing;
    bool function_sections;

    Buf *mmacosx_version_min;
    Buf *mios_version_min;
    Buf *root_out_name;
    Buf *test_filter;
    Buf *test_name_prefix;
    ZigPackage *root_package;
    Buf *zig_lib_dir;
    Buf *zig_std_dir;
    Buf *dynamic_linker_path;
    Buf *version_script_path; 

    const char **llvm_argv;
    size_t llvm_argv_len;

    const char **clang_argv;
    size_t clang_argv_len;
};

struct ZigVar {
    Buf name;
    ConstExprValue *const_value;
    ZigType *var_type;
    LLVMValueRef value_ref;
    IrInstruction *is_comptime;
    // which node is the declaration of the variable
    AstNode *decl_node;
    ZigLLVMDILocalVariable *di_loc_var;
    size_t src_arg_index;
    Scope *parent_scope;
    Scope *child_scope;
    LLVMValueRef param_value_ref;
    size_t mem_slot_index;
    IrExecutable *owner_exec;
    size_t ref_count;

    // In an inline loop, multiple variables may be created,
    // In this case, a reference to a variable should follow
    // this pointer to the redefined variable.
    ZigVar *next_var;

    ZigList<GlobalExport> export_list;

    uint32_t align_bytes;

    bool shadowable;
    bool src_is_const;
    bool gen_is_const;
    bool is_thread_local;
};

struct ErrorTableEntry {
    Buf name;
    uint32_t value;
    AstNode *decl_node;
    ZigType *set_with_only_this_in_it;
    // If we generate a constant error name value for this error, we memoize it here.
    // The type of this is array
    ConstExprValue *cached_error_name_val;
};

enum ScopeId {
    ScopeIdDecls,
    ScopeIdBlock,
    ScopeIdDefer,
    ScopeIdDeferExpr,
    ScopeIdVarDecl,
    ScopeIdCImport,
    ScopeIdLoop,
    ScopeIdSuspend,
    ScopeIdFnDef,
    ScopeIdCompTime,
    ScopeIdCoroPrelude,
    ScopeIdRuntime,
};

struct Scope {
    CodeGen *codegen;
    AstNode *source_node;

    // if the scope has a parent, this is it
    Scope *parent;

    ZigLLVMDIScope *di_scope;
    ScopeId id;
};

// This scope comes from global declarations or from
// declarations in a container declaration
// NodeTypeContainerDecl
struct ScopeDecls {
    Scope base;

    HashMap<Buf *, Tld *, buf_hash, buf_eql_buf> decl_table;
    ZigList<TldUsingNamespace *> use_decls;
    AstNode *safety_set_node;
    AstNode *fast_math_set_node;
    ZigType *import;
    // If this is a scope from a container, this is the type entry, otherwise null
    ZigType *container_type;
    Buf *bare_name;

    bool safety_off;
    bool fast_math_on;
    bool any_imports_failed;
};

enum LVal {
    LValNone,
    LValPtr,
};

// This scope comes from a block expression in user code.
// NodeTypeBlock
struct ScopeBlock {
    Scope base;

    Buf *name;
    IrBasicBlock *end_block;
    IrInstruction *is_comptime;
    ResultLocPeerParent *peer_parent;
    ZigList<IrInstruction *> *incoming_values;
    ZigList<IrBasicBlock *> *incoming_blocks;

    AstNode *safety_set_node;
    AstNode *fast_math_set_node;

    LVal lval;
    bool safety_off;
    bool fast_math_on;
};

// This scope is created from every defer expression.
// It's the code following the defer statement.
// NodeTypeDefer
struct ScopeDefer {
    Scope base;
};

// This scope is created from every defer expression.
// It's the parent of the defer expression itself.
// NodeTypeDefer
struct ScopeDeferExpr {
    Scope base;

    bool reported_err;
};

// This scope is created for every variable declaration inside an IrExecutable
// NodeTypeVariableDeclaration, NodeTypeParamDecl
struct ScopeVarDecl {
    Scope base;

    // The variable that creates this scope
    ZigVar *var;
};

// This scope is created for a @cImport
// NodeTypeFnCallExpr
struct ScopeCImport {
    Scope base;

    Buf buf;
};

// This scope is created for a loop such as for or while in order to
// make break and continue statements work.
// NodeTypeForExpr or NodeTypeWhileExpr
struct ScopeLoop {
    Scope base;

    LVal lval;
    Buf *name;
    IrBasicBlock *break_block;
    IrBasicBlock *continue_block;
    IrInstruction *is_comptime;
    ZigList<IrInstruction *> *incoming_values;
    ZigList<IrBasicBlock *> *incoming_blocks;
    ResultLocPeerParent *peer_parent;
};

// This scope blocks certain things from working such as comptime continue
// inside a runtime if expression.
// NodeTypeIfBoolExpr, NodeTypeWhileExpr, NodeTypeForExpr
struct ScopeRuntime {
    Scope base;

    IrInstruction *is_comptime;
};

// This scope is created for a suspend block in order to have labeled
// suspend for breaking out of a suspend and for detecting if a suspend
// block is inside a suspend block.
struct ScopeSuspend {
    Scope base;

    IrBasicBlock *resume_block;
    bool reported_err;
};

// This scope is created for a comptime expression.
// NodeTypeCompTime, NodeTypeSwitchExpr
struct ScopeCompTime {
    Scope base;
};


// This scope is created for a function definition.
// NodeTypeFnDef
struct ScopeFnDef {
    Scope base;

    ZigFn *fn_entry;
};

// This scope is created to indicate that the code in the scope
// is auto-generated coroutine prelude stuff.
struct ScopeCoroPrelude {
    Scope base;
};

// synchronized with code in define_builtin_compile_vars
enum AtomicOrder {
    AtomicOrderUnordered,
    AtomicOrderMonotonic,
    AtomicOrderAcquire,
    AtomicOrderRelease,
    AtomicOrderAcqRel,
    AtomicOrderSeqCst,
};

// synchronized with the code in define_builtin_compile_vars
enum AtomicRmwOp {
    AtomicRmwOp_xchg,
    AtomicRmwOp_add,
    AtomicRmwOp_sub,
    AtomicRmwOp_and,
    AtomicRmwOp_nand,
    AtomicRmwOp_or,
    AtomicRmwOp_xor,
    AtomicRmwOp_max,
    AtomicRmwOp_min,
};

// A basic block contains no branching. Branches send control flow
// to another basic block.
// Phi instructions must be first in a basic block.
// The last instruction in a basic block must be of type unreachable.
struct IrBasicBlock {
    ZigList<IrInstruction *> instruction_list;
    IrBasicBlock *other;
    Scope *scope;
    const char *name_hint;
    size_t debug_id;
    size_t ref_count;
    // index into the basic block list
    size_t index;
    LLVMBasicBlockRef llvm_block;
    LLVMBasicBlockRef llvm_exit_block;
    // The instruction that referenced this basic block and caused us to
    // analyze the basic block. If the same instruction wants us to emit
    // the same basic block, then we re-generate it instead of saving it.
    IrInstruction *ref_instruction;
    // When this is non-null, a branch to this basic block is only allowed
    // if the branch is comptime. The instruction points to the reason
    // the basic block must be comptime.
    IrInstruction *must_be_comptime_source_instr;
    IrInstruction *suspend_instruction_ref;
    bool already_appended;
    bool suspended;
    bool in_resume_stack;
};

// These instructions are in transition to having "pass 1" instructions
// and "pass 2" instructions. The pass 1 instructions are suffixed with Src
// and pass 2 are suffixed with Gen.
// Once all instructions are separated in this way, they'll have different
// base types for better type safety.
// Src instructions are generated by ir_gen_* functions in ir.cpp from AST.
// ir_analyze_* functions consume Src instructions and produce Gen instructions.
// ir_render_* functions in codegen.cpp consume Gen instructions and produce LLVM IR.
// Src instructions do not have type information; Gen instructions do.
enum IrInstructionId {
    IrInstructionIdInvalid,
    IrInstructionIdDeclVarSrc,
    IrInstructionIdDeclVarGen,
    IrInstructionIdBr,
    IrInstructionIdCondBr,
    IrInstructionIdSwitchBr,
    IrInstructionIdSwitchVar,
    IrInstructionIdSwitchElseVar,
    IrInstructionIdSwitchTarget,
    IrInstructionIdPhi,
    IrInstructionIdUnOp,
    IrInstructionIdBinOp,
    IrInstructionIdLoadPtr,
    IrInstructionIdLoadPtrGen,
    IrInstructionIdStorePtr,
    IrInstructionIdVectorElem,
    IrInstructionIdExtract,
    IrInstructionIdInsert,
    IrInstructionIdFieldPtr,
    IrInstructionIdStructFieldPtr,
    IrInstructionIdUnionFieldPtr,
    IrInstructionIdElemPtr,
    IrInstructionIdVarPtr,
    IrInstructionIdReturnPtr,
    IrInstructionIdCallSrc,
    IrInstructionIdCallGen,
    IrInstructionIdConst,
    IrInstructionIdReturn,
    IrInstructionIdCast,
    IrInstructionIdResizeSlice,
    IrInstructionIdContainerInitList,
    IrInstructionIdContainerInitFields,
    IrInstructionIdUnreachable,
    IrInstructionIdTypeOf,
    IrInstructionIdSetCold,
    IrInstructionIdSetRuntimeSafety,
    IrInstructionIdSetFloatMode,
    IrInstructionIdArrayType,
    IrInstructionIdPromiseType,
    IrInstructionIdSliceType,
    IrInstructionIdGlobalAsm,
    IrInstructionIdAsm,
    IrInstructionIdSizeOf,
    IrInstructionIdTestNonNull,
    IrInstructionIdOptionalUnwrapPtr,
    IrInstructionIdOptionalWrap,
    IrInstructionIdUnionTag,
    IrInstructionIdClz,
    IrInstructionIdCtz,
    IrInstructionIdPopCount,
    IrInstructionIdBswap,
    IrInstructionIdBitReverse,
    IrInstructionIdImport,
    IrInstructionIdCImport,
    IrInstructionIdCInclude,
    IrInstructionIdCDefine,
    IrInstructionIdCUndef,
    IrInstructionIdRef,
    IrInstructionIdRefGen,
    IrInstructionIdCompileErr,
    IrInstructionIdCompileLog,
    IrInstructionIdErrName,
    IrInstructionIdEmbedFile,
    IrInstructionIdCmpxchgSrc,
    IrInstructionIdCmpxchgGen,
    IrInstructionIdFence,
    IrInstructionIdTruncate,
    IrInstructionIdIntCast,
    IrInstructionIdFloatCast,
    IrInstructionIdIntToFloat,
    IrInstructionIdFloatToInt,
    IrInstructionIdBoolToInt,
    IrInstructionIdIntType,
    IrInstructionIdVectorType,
    IrInstructionIdShuffleVector,
    IrInstructionIdGather,
    IrInstructionIdScatter,
    IrInstructionIdSplat,
    IrInstructionIdBoolNot,
    IrInstructionIdMemset,
    IrInstructionIdMemcpy,
    IrInstructionIdSliceSrc,
    IrInstructionIdSliceGen,
    IrInstructionIdMemberCount,
    IrInstructionIdMemberType,
    IrInstructionIdMemberName,
    IrInstructionIdBreakpoint,
    IrInstructionIdReturnAddress,
    IrInstructionIdFrameAddress,
    IrInstructionIdHandle,
    IrInstructionIdAlignOf,
    IrInstructionIdOverflowOp,
    IrInstructionIdTestErrSrc,
    IrInstructionIdTestErrGen,
    IrInstructionIdMulAdd,
    IrInstructionIdFloatOp,
    IrInstructionIdUnwrapErrCode,
    IrInstructionIdUnwrapErrPayload,
    IrInstructionIdErrWrapCode,
    IrInstructionIdErrWrapPayload,
    IrInstructionIdFnProto,
    IrInstructionIdTestComptime,
    IrInstructionIdPtrCastSrc,
    IrInstructionIdPtrCastGen,
    IrInstructionIdBitCastSrc,
    IrInstructionIdBitCastGen,
    IrInstructionIdWidenOrShorten,
    IrInstructionIdIntToPtr,
    IrInstructionIdPtrToInt,
    IrInstructionIdIntToEnum,
    IrInstructionIdEnumToInt,
    IrInstructionIdIntToErr,
    IrInstructionIdErrToInt,
    IrInstructionIdCheckSwitchProngs,
    IrInstructionIdCheckStatementIsVoid,
    IrInstructionIdTypeName,
    IrInstructionIdDeclRef,
    IrInstructionIdPanic,
    IrInstructionIdTagName,
    IrInstructionIdTagType,
    IrInstructionIdFieldParentPtr,
    IrInstructionIdByteOffsetOf,
    IrInstructionIdBitOffsetOf,
    IrInstructionIdTypeInfo,
    IrInstructionIdHasField,
    IrInstructionIdTypeId,
    IrInstructionIdSetEvalBranchQuota,
    IrInstructionIdPtrType,
    IrInstructionIdAlignCast,
    IrInstructionIdImplicitCast,
    IrInstructionIdResolveResult,
    IrInstructionIdResetResult,
    IrInstructionIdResultPtr,
    IrInstructionIdOpaqueType,
    IrInstructionIdSetAlignStack,
    IrInstructionIdArgType,
    IrInstructionIdExport,
    IrInstructionIdErrorReturnTrace,
    IrInstructionIdErrorUnion,
    IrInstructionIdCancel,
    IrInstructionIdGetImplicitAllocator,
    IrInstructionIdCoroId,
    IrInstructionIdCoroAlloc,
    IrInstructionIdCoroSize,
    IrInstructionIdCoroBegin,
    IrInstructionIdCoroAllocFail,
    IrInstructionIdCoroSuspend,
    IrInstructionIdCoroEnd,
    IrInstructionIdCoroFree,
    IrInstructionIdCoroResume,
    IrInstructionIdCoroSave,
    IrInstructionIdCoroPromise,
    IrInstructionIdCoroAllocHelper,
    IrInstructionIdAtomicRmw,
    IrInstructionIdAtomicLoad,
    IrInstructionIdPromiseResultType,
    IrInstructionIdAwaitBookkeeping,
    IrInstructionIdSaveErrRetAddr,
    IrInstructionIdAddImplicitReturnType,
    IrInstructionIdMergeErrRetTraces,
    IrInstructionIdMarkErrRetTracePtr,
    IrInstructionIdErrSetCast,
    IrInstructionIdToBytes,
    IrInstructionIdFromBytes,
    IrInstructionIdCheckRuntimeScope,
    IrInstructionIdVectorToArray,
    IrInstructionIdArrayToVector,
    IrInstructionIdAssertZero,
    IrInstructionIdAssertNonNull,
    IrInstructionIdHasDecl,
    IrInstructionIdUndeclaredIdent,
    IrInstructionIdAllocaSrc,
    IrInstructionIdAllocaGen,
    IrInstructionIdEndExpr,
    IrInstructionIdPtrOfArrayToSlice,
    IrInstructionIdUnionInitNamedField,
};

struct IrInstruction {
    Scope *scope;
    AstNode *source_node;
    ConstExprValue value;
    size_t debug_id;
    LLVMValueRef llvm_value;
    // if ref_count is zero and the instruction has no side effects,
    // the instruction can be omitted in codegen
    size_t ref_count;
    // When analyzing IR, instructions that point to this instruction in the "old ir"
    // can find the instruction that corresponds to this value in the "new ir"
    // with this child field.
    IrInstruction *child;
    IrBasicBlock *owner_bb;
    IrInstructionId id;
    // true if this instruction was generated by zig and not from user code
    bool is_gen;
};

struct IrInstructionDeclVarSrc {
    IrInstruction base;

    ZigVar *var;
    IrInstruction *var_type;
    IrInstruction *align_value;
    IrInstruction *ptr;
};

struct IrInstructionDeclVarGen {
    IrInstruction base;

    ZigVar *var;
    IrInstruction *var_ptr;
};

struct IrInstructionCondBr {
    IrInstruction base;

    IrInstruction *condition;
    IrBasicBlock *then_block;
    IrBasicBlock *else_block;
    IrInstruction *is_comptime;
    ResultLoc *result_loc;
};

struct IrInstructionBr {
    IrInstruction base;

    IrBasicBlock *dest_block;
    IrInstruction *is_comptime;
};

struct IrInstructionSwitchBrCase {
    IrInstruction *value;
    IrBasicBlock *block;
};

struct IrInstructionSwitchBr {
    IrInstruction base;

    IrInstruction *target_value;
    IrBasicBlock *else_block;
    size_t case_count;
    IrInstructionSwitchBrCase *cases;
    IrInstruction *is_comptime;
    IrInstruction *switch_prongs_void;
};

struct IrInstructionSwitchVar {
    IrInstruction base;

    IrInstruction *target_value_ptr;
    IrInstruction **prongs_ptr;
    size_t prongs_len;
};

struct IrInstructionSwitchElseVar {
    IrInstruction base;

    IrInstruction *target_value_ptr;
    IrInstructionSwitchBr *switch_br;
};

struct IrInstructionSwitchTarget {
    IrInstruction base;

    IrInstruction *target_value_ptr;
};

struct IrInstructionPhi {
    IrInstruction base;

    size_t incoming_count;
    IrBasicBlock **incoming_blocks;
    IrInstruction **incoming_values;
    ResultLocPeerParent *peer_parent;
};

enum IrUnOp {
    IrUnOpInvalid,
    IrUnOpBinNot,
    IrUnOpNegation,
    IrUnOpNegationWrap,
    IrUnOpDereference,
    IrUnOpOptional,
};

struct IrInstructionUnOp {
    IrInstruction base;

    IrUnOp op_id;
    LVal lval;
    IrInstruction *value;
    ResultLoc *result_loc;
};

enum IrBinOp {
    IrBinOpInvalid,
    IrBinOpBoolOr,
    IrBinOpBoolAnd,
    IrBinOpCmpEq,
    IrBinOpCmpNotEq,
    IrBinOpCmpLessThan,
    IrBinOpCmpGreaterThan,
    IrBinOpCmpLessOrEq,
    IrBinOpCmpGreaterOrEq,
    IrBinOpBinOr,
    IrBinOpBinXor,
    IrBinOpBinAnd,
    IrBinOpBitShiftLeftLossy,
    IrBinOpBitShiftLeftExact,
    IrBinOpBitShiftRightLossy,
    IrBinOpBitShiftRightExact,
    IrBinOpAdd,
    IrBinOpAddWrap,
    IrBinOpSub,
    IrBinOpSubWrap,
    IrBinOpMult,
    IrBinOpMultWrap,
    IrBinOpDivUnspecified,
    IrBinOpDivExact,
    IrBinOpDivTrunc,
    IrBinOpDivFloor,
    IrBinOpRemUnspecified,
    IrBinOpRemRem,
    IrBinOpRemMod,
    IrBinOpArrayCat,
    IrBinOpArrayMult,
    IrBinOpMergeErrorSets,
};

struct IrInstructionBinOp {
    IrInstruction base;

    IrInstruction *op1;
    IrInstruction *op2;
    IrBinOp op_id;
    bool safety_check_on;
};

struct IrInstructionLoadPtr {
    IrInstruction base;

    IrInstruction *ptr;
};

struct IrInstructionVectorElem {
    IrInstruction base;

    IrInstruction *agg;
    IrInstruction *index;
    IrInstruction *result_loc;
};

struct IrInstructionExtract {
    IrInstruction base;

    IrInstruction *agg;
    IrInstruction *index;
};

struct IrInstructionInsert {
    IrInstruction base;

    IrInstruction *agg;
    IrInstruction *index;
    IrInstruction *value;
};

struct IrInstructionLoadPtrGen {
    IrInstruction base;

    IrInstruction *ptr;
    IrInstruction *result_loc;
};

struct IrInstructionStorePtr {
    IrInstruction base;

    bool allow_write_through_const;
    IrInstruction *ptr;
    IrInstruction *value;
};

struct IrInstructionFieldPtr {
    IrInstruction base;

    bool initializing;
    IrInstruction *container_ptr;
    Buf *field_name_buffer;
    IrInstruction *field_name_expr;
};

struct IrInstructionStructFieldPtr {
    IrInstruction base;

    IrInstruction *struct_ptr;
    TypeStructField *field;
    bool is_const;
};

struct IrInstructionUnionFieldPtr {
    IrInstruction base;

    bool safety_check_on;
    bool initializing;
    IrInstruction *union_ptr;
    TypeUnionField *field;
};

struct IrInstructionElemPtr {
    IrInstruction base;

    IrInstruction *array_ptr;
    IrInstruction *elem_index;
    IrInstruction *init_array_type;
    PtrLen ptr_len;
    bool safety_check_on;
};

struct IrInstructionVarPtr {
    IrInstruction base;

    ZigVar *var;
    ScopeFnDef *crossed_fndef_scope;
};

// For functions that have a return type for which handle_is_ptr is true, a
// result location pointer is the secret first parameter ("sret"). This
// instruction returns that pointer.
struct IrInstructionReturnPtr {
    IrInstruction base;
};

struct IrInstructionCallSrc {
    IrInstruction base;

    IrInstruction *fn_ref;
    ZigFn *fn_entry;
    size_t arg_count;
    IrInstruction **args;
    ResultLoc *result_loc;

    IrInstruction *async_allocator;
    IrInstruction *new_stack;
    FnInline fn_inline;
    bool is_async;
    bool is_comptime;
};

struct IrInstructionCallGen {
    IrInstruction base;

    IrInstruction *fn_ref;
    ZigFn *fn_entry;
    size_t arg_count;
    IrInstruction **args;
    IrInstruction *result_loc;

    IrInstruction *async_allocator;
    IrInstruction *new_stack;
    FnInline fn_inline;
    bool is_async;
};

struct IrInstructionConst {
    IrInstruction base;
};

// When an IrExecutable is not in a function, a return instruction means that
// the expression returns with that value, even though a return statement from
// an AST perspective is invalid.
struct IrInstructionReturn {
    IrInstruction base;

    IrInstruction *value;
};

enum CastOp {
    CastOpNoCast, // signifies the function call expression is not a cast
    CastOpNoop, // fn call expr is a cast, but does nothing
    CastOpIntToFloat,
    CastOpFloatToInt,
    CastOpBoolToInt,
    CastOpNumLitToConcrete,
    CastOpErrSet,
    CastOpBitCast,
};

// TODO get rid of this instruction, replace with instructions for each op code
struct IrInstructionCast {
    IrInstruction base;

    IrInstruction *value;
    ZigType *dest_type;
    CastOp cast_op;
};

struct IrInstructionResizeSlice {
    IrInstruction base;

    IrInstruction *operand;
    IrInstruction *result_loc;
};

struct IrInstructionContainerInitList {
    IrInstruction base;

    IrInstruction *container_type;
    IrInstruction *elem_type;
    size_t item_count;
    IrInstruction **elem_result_loc_list;
    IrInstruction *result_loc;
};

struct IrInstructionContainerInitFieldsField {
    Buf *name;
    AstNode *source_node;
    TypeStructField *type_struct_field;
    IrInstruction *result_loc;
};

struct IrInstructionContainerInitFields {
    IrInstruction base;

    IrInstruction *container_type;
    size_t field_count;
    IrInstructionContainerInitFieldsField *fields;
    IrInstruction *result_loc;
};

struct IrInstructionUnreachable {
    IrInstruction base;
};

struct IrInstructionTypeOf {
    IrInstruction base;

    IrInstruction *value;
};

struct IrInstructionSetCold {
    IrInstruction base;

    IrInstruction *is_cold;
};

struct IrInstructionSetRuntimeSafety {
    IrInstruction base;

    IrInstruction *safety_on;
};

struct IrInstructionSetFloatMode {
    IrInstruction base;

    IrInstruction *scope_value;
    IrInstruction *mode_value;
};

struct IrInstructionArrayType {
    IrInstruction base;

    IrInstruction *size;
    IrInstruction *child_type;
};

struct IrInstructionPtrType {
    IrInstruction base;

    IrInstruction *align_value;
    IrInstruction *child_type;
    uint32_t bit_offset_start;
    uint32_t host_int_bytes;
    PtrLen ptr_len;
    bool is_const;
    bool is_volatile;
    bool is_allow_zero;
};

struct IrInstructionPromiseType {
    IrInstruction base;

    IrInstruction *payload_type;
};

struct IrInstructionSliceType {
    IrInstruction base;

    IrInstruction *align_value;
    IrInstruction *child_type;
    bool is_const;
    bool is_volatile;
    bool is_allow_zero;
};

struct IrInstructionGlobalAsm {
    IrInstruction base;

    Buf *asm_code;
};

struct IrInstructionAsm {
    IrInstruction base;

    Buf *asm_template;
    AsmToken *token_list;
    size_t token_list_len;
    IrInstruction **input_list;
    IrInstruction **output_types;
    ZigVar **output_vars;
    size_t return_count;
    bool has_side_effects;
};

struct IrInstructionSizeOf {
    IrInstruction base;

    IrInstruction *type_value;
};

// returns true if nonnull, returns false if null
// this is so that `zeroes` sets maybe values to null
struct IrInstructionTestNonNull {
    IrInstruction base;

    IrInstruction *value;
};

// Takes a pointer to an optional value, returns a pointer
// to the payload.
struct IrInstructionOptionalUnwrapPtr {
    IrInstruction base;

    bool safety_check_on;
    bool initializing;
    IrInstruction *base_ptr;
};

struct IrInstructionCtz {
    IrInstruction base;

    IrInstruction *type;
    IrInstruction *op;
};

struct IrInstructionClz {
    IrInstruction base;

    IrInstruction *type;
    IrInstruction *op;
};

struct IrInstructionPopCount {
    IrInstruction base;

    IrInstruction *type;
    IrInstruction *op;
};

struct IrInstructionUnionTag {
    IrInstruction base;

    IrInstruction *value;
};

struct IrInstructionImport {
    IrInstruction base;

    IrInstruction *name;
};

struct IrInstructionRef {
    IrInstruction base;

    IrInstruction *value;
    bool is_const;
    bool is_volatile;
};

struct IrInstructionRefGen {
    IrInstruction base;

    IrInstruction *operand;
    IrInstruction *result_loc;
};

struct IrInstructionCompileErr {
    IrInstruction base;

    IrInstruction *msg;
};

struct IrInstructionCompileLog {
    IrInstruction base;

    size_t msg_count;
    IrInstruction **msg_list;
};

struct IrInstructionErrName {
    IrInstruction base;

    IrInstruction *value;
};

struct IrInstructionCImport {
    IrInstruction base;
};

struct IrInstructionCInclude {
    IrInstruction base;

    IrInstruction *name;
};

struct IrInstructionCDefine {
    IrInstruction base;

    IrInstruction *name;
    IrInstruction *value;
};

struct IrInstructionCUndef {
    IrInstruction base;

    IrInstruction *name;
};

struct IrInstructionEmbedFile {
    IrInstruction base;

    IrInstruction *name;
};

struct IrInstructionCmpxchgSrc {
    IrInstruction base;

    bool is_weak;
    IrInstruction *type_value;
    IrInstruction *ptr;
    IrInstruction *cmp_value;
    IrInstruction *new_value;
    IrInstruction *success_order_value;
    IrInstruction *failure_order_value;
    ResultLoc *result_loc;
};

struct IrInstructionCmpxchgGen {
    IrInstruction base;

    bool is_weak;
    AtomicOrder success_order;
    AtomicOrder failure_order;
    IrInstruction *ptr;
    IrInstruction *cmp_value;
    IrInstruction *new_value;
    IrInstruction *result_loc;
};

struct IrInstructionFence {
    IrInstruction base;

    IrInstruction *order_value;

    // if this instruction gets to runtime then we know these values:
    AtomicOrder order;
};

struct IrInstructionTruncate {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
};

struct IrInstructionIntCast {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
};

struct IrInstructionFloatCast {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
};

struct IrInstructionErrSetCast {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
};

struct IrInstructionToBytes {
    IrInstruction base;

    IrInstruction *target;
    ResultLoc *result_loc;
};

struct IrInstructionFromBytes {
    IrInstruction base;

    IrInstruction *dest_child_type;
    IrInstruction *target;
    ResultLoc *result_loc;
};

struct IrInstructionIntToFloat {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
};

struct IrInstructionFloatToInt {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
};

struct IrInstructionBoolToInt {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionIntType {
    IrInstruction base;

    IrInstruction *is_signed;
    IrInstruction *bit_count;
};

struct IrInstructionVectorType {
    IrInstruction base;

    IrInstruction *len;
    IrInstruction *elem_type;
};

struct IrInstructionBoolNot {
    IrInstruction base;

    IrInstruction *value;
};

struct IrInstructionMemset {
    IrInstruction base;

    IrInstruction *dest_ptr;
    IrInstruction *byte;
    IrInstruction *count;
};

struct IrInstructionMemcpy {
    IrInstruction base;

    IrInstruction *dest_ptr;
    IrInstruction *src_ptr;
    IrInstruction *count;
};

struct IrInstructionSliceSrc {
    IrInstruction base;

    bool safety_check_on;
    IrInstruction *ptr;
    IrInstruction *start;
    IrInstruction *end;
    ResultLoc *result_loc;
};

struct IrInstructionSliceGen {
    IrInstruction base;

    bool safety_check_on;
    IrInstruction *ptr;
    IrInstruction *start;
    IrInstruction *end;
    IrInstruction *result_loc;
};

struct IrInstructionMemberCount {
    IrInstruction base;

    IrInstruction *container;
};

struct IrInstructionMemberType {
    IrInstruction base;

    IrInstruction *container_type;
    IrInstruction *member_index;
};

struct IrInstructionMemberName {
    IrInstruction base;

    IrInstruction *container_type;
    IrInstruction *member_index;
};

struct IrInstructionBreakpoint {
    IrInstruction base;
};

struct IrInstructionReturnAddress {
    IrInstruction base;
};

struct IrInstructionFrameAddress {
    IrInstruction base;
};

struct IrInstructionHandle {
    IrInstruction base;
};

enum IrOverflowOp {
    IrOverflowOpAdd,
    IrOverflowOpSub,
    IrOverflowOpMul,
    IrOverflowOpShl,
};

struct IrInstructionOverflowOp {
    IrInstruction base;

    IrOverflowOp op;
    IrInstruction *type_value;
    IrInstruction *op1;
    IrInstruction *op2;
    IrInstruction *result_ptr;

    ZigType *result_ptr_type;
};

struct IrInstructionMulAdd {
    IrInstruction base;

    IrInstruction *type_value;
    IrInstruction *op1;
    IrInstruction *op2;
    IrInstruction *op3;
};

struct IrInstructionAlignOf {
    IrInstruction base;

    IrInstruction *type_value;
};

// returns true if error, returns false if not error
struct IrInstructionTestErrSrc {
    IrInstruction base;

    bool resolve_err_set;
    IrInstruction *base_ptr;
};

struct IrInstructionTestErrGen {
    IrInstruction base;

    IrInstruction *err_union;
};

// Takes an error union pointer, returns a pointer to the error code.
struct IrInstructionUnwrapErrCode {
    IrInstruction base;

    bool initializing;
    IrInstruction *err_union_ptr;
};

struct IrInstructionUnwrapErrPayload {
    IrInstruction base;

    bool safety_check_on;
    bool initializing;
    IrInstruction *value;
};

struct IrInstructionOptionalWrap {
    IrInstruction base;

    IrInstruction *operand;
    IrInstruction *result_loc;
};

struct IrInstructionErrWrapPayload {
    IrInstruction base;

    IrInstruction *operand;
    IrInstruction *result_loc;
};

struct IrInstructionErrWrapCode {
    IrInstruction base;

    IrInstruction *operand;
    IrInstruction *result_loc;
};

struct IrInstructionFnProto {
    IrInstruction base;

    IrInstruction **param_types;
    IrInstruction *align_value;
    IrInstruction *return_type;
    IrInstruction *async_allocator_type_value;
    bool is_var_args;
};

// true if the target value is compile time known, false otherwise
struct IrInstructionTestComptime {
    IrInstruction base;

    IrInstruction *value;
};

struct IrInstructionPtrCastSrc {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *ptr;
    bool safety_check_on;
};

struct IrInstructionPtrCastGen {
    IrInstruction base;

    IrInstruction *ptr;
    bool safety_check_on;
};

struct IrInstructionBitCastSrc {
    IrInstruction base;

    IrInstruction *operand;
    ResultLocBitCast *result_loc_bit_cast;
};

struct IrInstructionBitCastGen {
    IrInstruction base;

    IrInstruction *operand;
};

struct IrInstructionWidenOrShorten {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionPtrToInt {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionIntToPtr {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
};

struct IrInstructionIntToEnum {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
};

struct IrInstructionEnumToInt {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionIntToErr {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionErrToInt {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionCheckSwitchProngsRange {
    IrInstruction *start;
    IrInstruction *end;
};

struct IrInstructionCheckSwitchProngs {
    IrInstruction base;

    IrInstruction *target_value;
    IrInstructionCheckSwitchProngsRange *ranges;
    size_t range_count;
    bool have_else_prong;
};

struct IrInstructionCheckStatementIsVoid {
    IrInstruction base;

    IrInstruction *statement_value;
};

struct IrInstructionTypeName {
    IrInstruction base;

    IrInstruction *type_value;
};

struct IrInstructionDeclRef {
    IrInstruction base;

    LVal lval;
    Tld *tld;
};

struct IrInstructionPanic {
    IrInstruction base;

    IrInstruction *msg;
};

struct IrInstructionTagName {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionTagType {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionFieldParentPtr {
    IrInstruction base;

    IrInstruction *type_value;
    IrInstruction *field_name;
    IrInstruction *field_ptr;
    TypeStructField *field;
};

struct IrInstructionByteOffsetOf {
    IrInstruction base;

    IrInstruction *type_value;
    IrInstruction *field_name;
};

struct IrInstructionBitOffsetOf {
    IrInstruction base;

    IrInstruction *type_value;
    IrInstruction *field_name;
};

struct IrInstructionTypeInfo {
    IrInstruction base;

    IrInstruction *type_value;
};

struct IrInstructionHasField {
    IrInstruction base;

    IrInstruction *container_type;
    IrInstruction *field_name;
};

struct IrInstructionTypeId {
    IrInstruction base;

    IrInstruction *type_value;
};

struct IrInstructionSetEvalBranchQuota {
    IrInstruction base;

    IrInstruction *new_quota;
};

struct IrInstructionAlignCast {
    IrInstruction base;

    IrInstruction *align_bytes;
    IrInstruction *target;
};

struct IrInstructionOpaqueType {
    IrInstruction base;
};

struct IrInstructionSetAlignStack {
    IrInstruction base;

    IrInstruction *align_bytes;
};

struct IrInstructionArgType {
    IrInstruction base;

    IrInstruction *fn_type;
    IrInstruction *arg_index;
};

struct IrInstructionExport {
    IrInstruction base;

    IrInstruction *name;
    IrInstruction *linkage;
    IrInstruction *target;
};

struct IrInstructionErrorReturnTrace {
    IrInstruction base;

    enum Optional {
        Null,
        NonNull,
    } optional;
};

struct IrInstructionErrorUnion {
    IrInstruction base;

    IrInstruction *err_set;
    IrInstruction *payload;
};

struct IrInstructionCancel {
    IrInstruction base;

    IrInstruction *target;
};

enum ImplicitAllocatorId {
    ImplicitAllocatorIdArg,
    ImplicitAllocatorIdLocalVar,
};

struct IrInstructionGetImplicitAllocator {
    IrInstruction base;

    ImplicitAllocatorId id;
};

struct IrInstructionCoroId {
    IrInstruction base;

    IrInstruction *promise_ptr;
};

struct IrInstructionCoroAlloc {
    IrInstruction base;

    IrInstruction *coro_id;
};

struct IrInstructionCoroSize {
    IrInstruction base;
};

struct IrInstructionCoroBegin {
    IrInstruction base;

    IrInstruction *coro_id;
    IrInstruction *coro_mem_ptr;
};

struct IrInstructionCoroAllocFail {
    IrInstruction base;

    IrInstruction *err_val;
};

struct IrInstructionCoroSuspend {
    IrInstruction base;

    IrInstruction *save_point;
    IrInstruction *is_final;
};

struct IrInstructionCoroEnd {
    IrInstruction base;
};

struct IrInstructionCoroFree {
    IrInstruction base;

    IrInstruction *coro_id;
    IrInstruction *coro_handle;
};

struct IrInstructionCoroResume {
    IrInstruction base;

    IrInstruction *awaiter_handle;
};

struct IrInstructionCoroSave {
    IrInstruction base;

    IrInstruction *coro_handle;
};

struct IrInstructionCoroPromise {
    IrInstruction base;

    IrInstruction *coro_handle;
};

struct IrInstructionCoroAllocHelper {
    IrInstruction base;

    IrInstruction *realloc_fn;
    IrInstruction *coro_size;
};

struct IrInstructionAtomicRmw {
    IrInstruction base;

    IrInstruction *operand_type;
    IrInstruction *ptr;
    IrInstruction *op;
    AtomicRmwOp resolved_op;
    IrInstruction *operand;
    IrInstruction *ordering;
    AtomicOrder resolved_ordering;
};

struct IrInstructionAtomicLoad {
    IrInstruction base;

    IrInstruction *operand_type;
    IrInstruction *ptr;
    IrInstruction *ordering;
    AtomicOrder resolved_ordering;
};

struct IrInstructionPromiseResultType {
    IrInstruction base;

    IrInstruction *promise_type;
};

struct IrInstructionAwaitBookkeeping {
    IrInstruction base;

    IrInstruction *promise_result_type;
};

struct IrInstructionSaveErrRetAddr {
    IrInstruction base;
};

struct IrInstructionAddImplicitReturnType {
    IrInstruction base;

    IrInstruction *value;
};

struct IrInstructionMergeErrRetTraces {
    IrInstruction base;

    IrInstruction *coro_promise_ptr;
    IrInstruction *src_err_ret_trace_ptr;
    IrInstruction *dest_err_ret_trace_ptr;
};

struct IrInstructionMarkErrRetTracePtr {
    IrInstruction base;

    IrInstruction *err_ret_trace_ptr;
};

// For float ops which take a single argument
struct IrInstructionFloatOp {
    IrInstruction base;

    BuiltinFnId op;
    IrInstruction *type;
    IrInstruction *op1;
};

struct IrInstructionCheckRuntimeScope {
    IrInstruction base;

    IrInstruction *scope_is_comptime;
    IrInstruction *is_comptime;
};

struct IrInstructionBswap {
    IrInstruction base;

    IrInstruction *type;
    IrInstruction *op;
};

struct IrInstructionBitReverse {
    IrInstruction base;

    IrInstruction *type;
    IrInstruction *op;
};

struct IrInstructionArrayToVector {
    IrInstruction base;

    IrInstruction *array;
};

struct IrInstructionVectorToArray {
    IrInstruction base;

    IrInstruction *vector;
    IrInstruction *result_loc;
};

struct IrInstructionShuffleVector {
    IrInstruction base;

    IrInstruction *scalar_type;
    IrInstruction *a;
    IrInstruction *b;
    IrInstruction *mask; // This is in zig-format, not llvm format
};

// scatter and gather had to be split because scatter
// has side effects and gather does not
struct IrInstructionMaskedVector {
    IrInstruction base;

    IrInstruction *scalar_type;
    IrInstruction *ptr; // pointer or vector of pointers
    IrInstruction *vector;
    IrInstruction *mask;
};

// typedef can't be used here because of C++ dumbness
struct IrInstructionGather {
    IrInstruction base;

    IrInstruction *scalar_type;
    IrInstruction *ptr; // pointer or vector of pointers
    IrInstruction *vector;
    IrInstruction *mask;
};

// typedef can't be used here because of C++ dumbness
struct IrInstructionScatter {
    IrInstruction base;

    IrInstruction *scalar_type;
    IrInstruction *ptr; // pointer or vector of pointers
    IrInstruction *vector;
    IrInstruction *mask;
};

struct IrInstructionSplat {
    IrInstruction base;

    IrInstruction *len;
    IrInstruction *scalar;
};

struct IrInstructionAssertZero {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionAssertNonNull {
    IrInstruction base;

    IrInstruction *target;
};

struct IrInstructionUnionInitNamedField {
    IrInstruction base;

    IrInstruction *union_type;
    IrInstruction *field_name;
    IrInstruction *field_result_loc;
    IrInstruction *result_loc;
};

struct IrInstructionHasDecl {
    IrInstruction base;

    IrInstruction *container;
    IrInstruction *name;
};

struct IrInstructionUndeclaredIdent {
    IrInstruction base;

    Buf *name;
};

struct IrInstructionAllocaSrc {
    IrInstruction base;

    IrInstruction *align;
    IrInstruction *is_comptime;
    const char *name_hint;
};

struct IrInstructionAllocaGen {
    IrInstruction base;

    uint32_t align;
    const char *name_hint;
};

struct IrInstructionEndExpr {
    IrInstruction base;

    IrInstruction *value;
    ResultLoc *result_loc;
};

struct IrInstructionImplicitCast {
    IrInstruction base;

    IrInstruction *dest_type;
    IrInstruction *target;
    ResultLoc *result_loc;
};

// This one is for writing through the result pointer.
struct IrInstructionResolveResult {
    IrInstruction base;

    ResultLoc *result_loc;
    IrInstruction *ty;
};

// This one is when you want to read the value of the result.
// You have to give the value in case it is comptime.
struct IrInstructionResultPtr {
    IrInstruction base;

    ResultLoc *result_loc;
    IrInstruction *result;
};

struct IrInstructionResetResult {
    IrInstruction base;

    ResultLoc *result_loc;
};

struct IrInstructionPtrOfArrayToSlice {
    IrInstruction base;

    IrInstruction *operand;
    IrInstruction *result_loc;
};

enum ResultLocId {
    ResultLocIdInvalid,
    ResultLocIdNone,
    ResultLocIdVar,
    ResultLocIdReturn,
    ResultLocIdPeer,
    ResultLocIdPeerParent,
    ResultLocIdInstruction,
    ResultLocIdBitCast,
};

// Additions to this struct may need to be handled in 
// ir_reset_result
struct ResultLoc {
    ResultLocId id;
    bool written;
    bool allow_write_through_const;
    IrInstruction *resolved_loc; // result ptr 
    IrInstruction *source_instruction;
    IrInstruction *gen_instruction; // value to store to the result loc
    ZigType *implicit_elem_type;
};

struct ResultLocNone {
    ResultLoc base;
};

struct ResultLocVar {
    ResultLoc base;

    ZigVar *var;
};

struct ResultLocReturn {
    ResultLoc base;
};

struct IrSuspendPosition {
    size_t basic_block_index;
    size_t instruction_index;
};

struct ResultLocPeerParent {
    ResultLoc base;

    bool skipped;
    bool done_resuming;
    IrBasicBlock *end_bb;
    ResultLoc *parent;
    ZigList<ResultLocPeer *> peers;
    ZigType *resolved_type;
    IrInstruction *is_comptime;
};

struct ResultLocPeer {
    ResultLoc base;

    ResultLocPeerParent *parent;
    IrBasicBlock *next_bb;
    IrSuspendPosition suspend_pos;
};

// The result location is the source instruction
struct ResultLocInstruction {
    ResultLoc base;
};

// The source_instruction is the destination type
struct ResultLocBitCast {
    ResultLoc base;

    ResultLoc *parent;
};

static const size_t slice_ptr_index = 0;
static const size_t slice_len_index = 1;

static const size_t maybe_child_index = 0;
static const size_t maybe_null_index = 1;

static const size_t err_union_err_index = 0;
static const size_t err_union_payload_index = 1;

// TODO call graph analysis to find out what this number needs to be for every function
// MUST BE A POWER OF TWO.
static const size_t stack_trace_ptr_count = 32;

// these belong to the async function
#define RETURN_ADDRESSES_FIELD_NAME "return_addresses"
#define ERR_RET_TRACE_FIELD_NAME "err_ret_trace"
#define RESULT_FIELD_NAME "result"
#define ASYNC_REALLOC_FIELD_NAME "reallocFn"
#define ASYNC_SHRINK_FIELD_NAME "shrinkFn"
#define ATOMIC_STATE_FIELD_NAME "atomic_state"
// these point to data belonging to the awaiter
#define ERR_RET_TRACE_PTR_FIELD_NAME "err_ret_trace_ptr"
#define RESULT_PTR_FIELD_NAME "result_ptr"

#define NAMESPACE_SEP_CHAR '.'
#define NAMESPACE_SEP_STR "."

#define CACHE_OUT_SUBDIR "o"
#define CACHE_HASH_SUBDIR "h"

enum FloatMode {
    FloatModeStrict,
    FloatModeOptimized,
};

enum FnWalkId {
    FnWalkIdAttrs,
    FnWalkIdCall,
    FnWalkIdTypes,
    FnWalkIdVars,
    FnWalkIdInits,
};

struct FnWalkAttrs {
    ZigFn *fn;
    unsigned gen_i;
};

struct FnWalkCall {
    ZigList<LLVMValueRef> *gen_param_values;
    IrInstructionCallGen *inst;
    bool is_var_args;
};

struct FnWalkTypes {
    ZigList<ZigLLVMDIType *> *param_di_types;
    ZigList<LLVMTypeRef> *gen_param_types;
};

struct FnWalkVars {
    ZigType *import;
    LLVMValueRef llvm_fn;
    ZigFn *fn;
    ZigVar *var;
    unsigned gen_i;
};

struct FnWalkInits {
    LLVMValueRef llvm_fn;
    ZigFn *fn;
    unsigned gen_i;
};

struct FnWalk {
    FnWalkId id;
    union {
        FnWalkAttrs attrs;
        FnWalkCall call;
        FnWalkTypes types;
        FnWalkVars vars;
        FnWalkInits inits;
    } data;
};

#endif
