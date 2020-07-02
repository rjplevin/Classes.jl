#
# Functional interface to MacroTools' dict-based expression creation functions
# TBD: suggest adding these (without requiring dict) to MacroTools
#
function emit_struct(name::Symbol, supertype::Symbol, mutable::Bool, params::Vector, fields::Vector, ctors::Vector)
    fieldtups = [(tup[1], tup[2]) for tup in map(splitarg, fields)]
    d = Dict(:name=>name, :supertype=>supertype, :mutable=>mutable, :params=>params, :fields=>fieldtups, :constructors=>ctors)
    combinestructdef(d)
end

function emit_function(name::Symbol, body; args::Vector=[], kwargs::Vector=[], rtype=nothing, params::Vector=[], wparams::Vector=[])
    d = Dict(:name=>name, :args=>args, :kwargs=>kwargs, :body=>body, :params=>params, :whereparams=>wparams)
    if rtype !== nothing
        d[:rtype] = rtype
    end
    combinedef(d)
end

abs_symbol(cls::Symbol) = Symbol("Abstract", cls)

# Since nameof() doesn't cover all the cases we need, we define our own
typename(t) = t
typename(t::TypeVar) = t.name

# fieldnames(DataType)
# (:name, :super, :parameters, :types, :names, :instance, :layout, :size, :ninitialized, :uid, :abstract, :mutable, :hasfreetypevars,
# :isconcretetype, :isdispatchtuple, :isbitstype, :zeroinit, :isinlinealloc, Symbol("llvm::StructType"), Symbol("llvm::DIType"))
#
# if dtype.hasfreetypevars, dtype.types is like svec(XYZ<:ABC,...)

function _translate_ivar(d::Dict, ivar)
    if ! @capture(ivar, vname_::vtype_ | vname_)
        error("Expected field definition, got $ivar")
    end

    if vtype === nothing
        return ivar    # no type, nothing to translate
    end

    vtype = get(d, vtype, vtype)    # translate parameterized types
    return :($vname::$vtype)
end

function _translate_where(d::Dict, wparam::TypeVar)
    # supname = :Any
    supname = wparam.ub          # TBD: not sure this suffices
    name = wparam.name
    name = get(d, name, name)    # translate, if a type parameter, else pass through

    return :($name <: $supname)
end

# If a symbol is already a gensym, extract the symbol and re-gensym with it
regensym(s) = MacroTools.isgensym(s) ? gensym(Symbol(MacroTools.gensymname(s))) : gensym(s)
