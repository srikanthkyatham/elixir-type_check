defmodule TypeCheck.Macros do
  defmacro __using__(_options) do
    quote do
      import TypeCheck.Macros

      Module.register_attribute(__MODULE__, TypeCheck.TypeDefs, accumulate: true)
      Module.register_attribute(__MODULE__, TypeCheck.Specs, accumulate: true)
      @before_compile TypeCheck.Macros
    end
  end

  defmacro __before_compile__(env) do
    defs =
      Module.get_attribute(env.module, TypeCheck.TypeDefs)

    Module.create(Module.concat(env.module, TypeCheck), quote do
      @moduledoc false
      # This extra module is created
      # so that we can already access the custom user types
      # at compile-time
      # _inside_ the module they will be part of
      unquote(defs)
    end, env)

    # And now, override all specs:
    definitions = Module.definitions_in(env.module)
    specs = Module.get_attribute(env.module, TypeCheck.Specs)
    spec_quotes = wrap_functions_with_specs(specs, definitions)

    # Time to combine it all
    quote do
      import __MODULE__.TypeCheck

      unquote(spec_quotes)
    end
  end

  defp wrap_functions_with_specs(specs, definitions) do
    for {name, line, arity, clean_params, params_spec_code, return_spec_code} <- specs do
      unless {name, arity} in definitions do
        raise ArgumentError, "spec for undefined function #{name}/#{arity}"
      end

      TypeCheck.Spec.wrap_function_with_spec(name, line, arity, clean_params, params_spec_code, return_spec_code)
    end
  end

  defmacro type(typedef) do
    define_type(typedef, :type, __CALLER__)
  end

  defmacro typep(typedef) do
    define_type(typedef, :typep, __CALLER__)
  end

  defmacro opaque(typedef) do
    define_type(typedef, :opaque, __CALLER__)
  end

  defmacro spec(specdef) do
    define_spec(specdef, __CALLER__)
  end

  defp define_type(typedef = {:"::", _meta, [name_with_maybe_params, type]}, kind, caller) do
    new_typedoc =
      case kind do
        :typep -> false
        _ ->
          append_typedoc(caller, """
          This type is managed by `TypeCheck`,
          which allows checking values against the type at runtime.

          Full definition: #{type_definition_doc(name_with_maybe_params, type, kind)}
          """)
      end
    type = TypeCheck.Internals.PreExpander.rewrite(type, caller)

    res = type_fun_definition(name_with_maybe_params, type)
    quote do
      case unquote(kind) do
        :opaque ->
          @typedoc unquote(new_typedoc)
          @opaque unquote(typedef)
        :type ->
          @typedoc unquote(new_typedoc)
          @type unquote(typedef)
        :typep ->
          @typep unquote(typedef)
      end
      unquote(res)
      Module.put_attribute(__MODULE__, TypeCheck.TypeDefs, unquote(Macro.escape(res)))
    end
  end

  defp append_typedoc(caller, extra_doc) do
    {_line, old_doc} = Module.get_attribute(caller.module, :typedoc) || {0, ""}
    newdoc = old_doc <> extra_doc
    Module.delete_attribute(caller.module, :typedoc)
    newdoc
  end

  defp type_definition_doc(name_with_maybe_params, type_ast, kind) do
    head = Macro.to_string(name_with_maybe_params)
    if kind == :opaque do
       """
       `head` _(opaque type)_
       """
    else
      """
      `#{head} :: #{Macro.to_string(type_ast)}`
      """
    end
  end

  defp type_fun_definition(name_with_params, type) do
    quote do
      @doc false
      def unquote(name_with_params) do
        import TypeCheck.Builtin
        unquote(type)
      end
    end
  end

  defp define_spec(specdef = {:"::", _meta, [name_with_params_ast, return_type_ast]}, caller) do
    {name, params_ast} = Macro.decompose_call(name_with_params_ast)
    arity = length(params_ast)
    # TODO currently assumes the params are directly types
    # rather than the possibility of named types like `x :: integer()`

    require TypeCheck.Type
    param_types = Enum.map(params_ast, &TypeCheck.Type.build_unescaped(&1, caller))
    return_type = TypeCheck.Type.build_unescaped(return_type_ast, caller)

    clean_params =
      Macro.generate_arguments(arity, caller.module)
    {params_spec_code, return_spec_code} = TypeCheck.Spec.prepare_spec_wrapper_code(specdef, name, param_types, clean_params, return_type, caller)

    spec_fun_name = :"__type_check_spec_for_#{name}/#{arity}__"
    quote location: :keep do
      Module.put_attribute(__MODULE__, TypeCheck.Specs, {unquote(name), unquote(caller.line), unquote(arity), unquote(Macro.escape(clean_params)), unquote(Macro.escape(params_spec_code)), unquote(Macro.escape(return_spec_code))})

      def unquote(spec_fun_name)() do
        import TypeCheck.Builtin
        %TypeCheck.Spec{name: unquote(name), param_types: unquote(params_ast), return_type: unquote(return_type_ast)}
      end
    end
  end
end