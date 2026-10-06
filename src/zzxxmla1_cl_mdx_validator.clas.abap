*----------------------------------------------------------------------------------------------------------------------*
* olap4abap - XMLA server with an MDX engine for SAP BW               https://github.com/arcanist123/olap4abap
* Copyright (c) 2026 the olap4abap authors
*
* This program and the accompanying materials are made available under the terms of the Eclipse Public License 2.0,
* which is available at https://www.eclipse.org/legal/epl-2.0/
* SPDX-License-Identifier: EPL-2.0
*
* olap4abap contains code derived from Mondrian (Eclipse Public License 1.0): Copyright (C) 1998-2005 Julian Hyde,
* Copyright (C) 2005-2021 Hitachi Vantara and others, Copyright (C) 2021-2025 Sergei Semenkov. See the NOTICE file.
*----------------------------------------------------------------------------------------------------------------------*
"! MDX validator: the port of Query.resolve and ValidatorImpl, with FunUtil.resolveFunArgs, Id.accept and
"! Util.lookup, TypeUtil.canConvert and the resolvers of the function table (ZZXXMLA1_CL_MDX_FUNTABLE). It turns the parse
"! tree of a query into resolved expressions (ZZXXMLA1_CL_MDX_NODE): an identifier becomes the element of the cube it
"! names (lookupCompound of ZZXXMLA1_CL_MDX_SCHEMA_READER), a call becomes a call of the function definition whose
"! signature the arguments convert to at the lowest cost, and every node gets its type. All resolvers that resolve by
"! their signatures work (SimpleResolver and the MultiResolvers); of those with resolution logic of their own the
"! braces (SetFunDef), parentheses (TupleFunDef), CrossJoin / * (CrossJoinFunDef), Order and Cast are ported, a call of the others is
"! a fault "... is not implemented yet". Calculated members (WITH MEMBER) are created first and added to the schema
"! reader (Formula.createElement), then their formulas and properties are resolved and their format expressions found
"! (Formula.accept, getFormatExp). Named sets (WITH SET, SetBase) and aliases (expression AS name, Query.ScopedNamedSet,
"! registered for the call around the AS) are found by their one-segment names and become NamedSetExpr nodes, their
"! expressions resolved when they are first used. Errors have texts.
CLASS zzxxmla1_cl_mdx_validator DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_node TYPE REF TO zzxxmla1_cl_mdx_node.

    METHODS constructor
      IMPORTING schema_reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    "! Query.resolve(Validator): the formulas, the axes (each a set; no axis twice, none missing) and the slicer are
    "! validated in place; no hierarchy may be used definitely on more than one axis (the slicer counts).
    METHODS resolve_query
      CHANGING query TYPE zzxxmla1_cl_mdx_parser=>ty_query
      RAISING  zzxxmla1_cx_xmla.
    "! Validator.validate: the resolved expression; with scalar it must not be a set (MdxMemberExpIsSet).
    METHODS validate
      IMPORTING node          TYPE ty_node
                scalar        TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE ty_node
      RAISING   zzxxmla1_cx_xmla.

  PRIVATE SECTION.
    TYPES ty_t_node TYPE zzxxmla1_cl_mdx_node=>ty_t_node.
    TYPES ty_type TYPE REF TO zzxxmla1_cl_mdx_type.
    TYPES ty_t_category TYPE zzxxmla1_cl_mdx_funtable=>ty_t_category.
    TYPES:
      "! Resolver.Conversion (TypeUtil.ConversionImpl); ordinal counts from 0 as in the reference
      BEGIN OF ty_conversion,
        from    TYPE i,
        to      TYPE i,
        ordinal TYPE i,
        cost    TYPE i,
      END OF ty_conversion,
      ty_t_conversion TYPE STANDARD TABLE OF ty_conversion WITH EMPTY KEY.
    TYPES:
      "! an entry of the validation stack: an axis or a node being validated
      BEGIN OF ty_frame,
        kind TYPE string,
        node TYPE ty_node,
      END OF ty_frame.
    TYPES:
      BEGIN OF ty_resolved,
        node     TYPE ty_node,
        resolved TYPE ty_node,
      END OF ty_resolved.
    TYPES:
      "! a named set of the query (WITH SET, SetBase) or an alias (AS, Query.ScopedNamedSet)
      BEGIN OF ty_named_set,
        name       TYPE string,
        key        TYPE string,     " unique within the query (NamedSet.getNameUniqueWithinQuery)
        dynamic    TYPE abap_bool,  " an alias
        scope      TYPE ty_node,    " an alias: the call whose argument the AS is
        expression TYPE ty_node,    " as parsed
        node       TYPE ty_node,    " the NamedSetExpr, once the expression is resolved
        busy       TYPE abap_bool,  " the expression is being resolved
      END OF ty_named_set.
    " the categories of olap.Category, as zzxxmla1_cl_mdx_type=>c_category
    CONSTANTS:
      BEGIN OF c_category,
        unknown   TYPE i VALUE 0,
        array     TYPE i VALUE 1,
        dimension TYPE i VALUE 2,
        hierarchy TYPE i VALUE 3,
        level     TYPE i VALUE 4,
        logical   TYPE i VALUE 5,
        member    TYPE i VALUE 6,
        numeric   TYPE i VALUE 7,
        set       TYPE i VALUE 8,
        string    TYPE i VALUE 9,
        tuple     TYPE i VALUE 10,
        symbol    TYPE i VALUE 11,
        cube      TYPE i VALUE 12,
        value     TYPE i VALUE 13,
        integer   TYPE i VALUE 15,
        null      TYPE i VALUE 16,
        empty     TYPE i VALUE 17,
        datetime  TYPE i VALUE 18,
        constant  TYPE i VALUE 64,
      END OF c_category.

    DATA schema_reader  TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    DATA funtable       TYPE REF TO zzxxmla1_cl_mdx_funtable.
    DATA stack          TYPE STANDARD TABLE OF ty_frame WITH EMPTY KEY.
    DATA resolved_nodes TYPE HASHED TABLE OF ty_resolved WITH UNIQUE KEY node.
    DATA named_sets     TYPE STANDARD TABLE OF ty_named_set WITH EMPTY KEY.

    "! Query's alias finder (registerAlias): an argument "expression AS name" of a call is an alias whose scope is the
    "! call; in the whole tree.
    METHODS register_aliases
      IMPORTING node TYPE ty_node.
    "! Query.lookupScopedNamedSet: the alias of the one-segment name whose scope is the deepest on the validation stack;
    "! 0 if there is none.
    METHODS lookup_alias
      IMPORTING segments      TYPE zzxxmla1_cl_mdx_node=>ty_t_segment
      RETURNING VALUE(result) TYPE i.
    "! Query.lookupNamedSet: the named set (WITH SET) of the one-segment name; 0 if there is none.
    METHODS lookup_query_set
      IMPORTING segments      TYPE zzxxmla1_cl_mdx_node=>ty_t_segment
      RETURNING VALUE(result) TYPE i.
    "! The NamedSetExpr of a named set, its expression resolved the first time (SetBase.validate; an alias's member or
    "! tuple becomes a set, ScopedNamedSet.validate); the type of a member or tuple is a set of it (SetBase.getType).
    METHODS named_set_expression
      IMPORTING index         TYPE i
      RETURNING VALUE(result) TYPE ty_node
      RAISING   zzxxmla1_cx_xmla.
    "! AsFunDef.ResolverImpl: a set (or what converts to one) AS an alias.
    METHODS resolve_as
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.

    "! QueryAxis.resolve: a member, tuple, dimension or hierarchy becomes a set, anything else is no axis.
    METHODS resolve_axis
      IMPORTING axis_name  TYPE string
      CHANGING  expression TYPE ty_node
      RAISING   zzxxmla1_cx_xmla.
    METHODS accept
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_node
      RAISING   zzxxmla1_cx_xmla.
    "! Id.accept: a reserved word alone is a symbol, otherwise Util.lookup: the element the identifier names.
    METHODS validate_id
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_node
      RAISING   zzxxmla1_cx_xmla.
    "! Util.lookup with allowProp, before the element is looked up: an identifier whose last segment is a name and
    "! whose other segments name a member, else a level, with a property of that name (Util.isValidProperty) is a call
    "! of the property (Syntax.Property) on the member or level, validated as such; unbound if it is none.
    METHODS lookup_property_reference
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_node
      RAISING   zzxxmla1_cx_xmla.
    "! UnresolvedFunCall.accept: the arguments, then the function definition (getDef) and its result type.
    METHODS validate_call
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_node
      RAISING   zzxxmla1_cx_xmla.
    "! Util.createExpr with the type of the element.
    METHODS element_expression
      IMPORTING element       TYPE zzxxmla1_cl_mdx_schema_reader=>ty_element
      RETURNING VALUE(result) TYPE ty_node.
    "! ValidatorImpl.getDef: the resolver whose match needs the cheapest conversions; its conversions are applied.
    METHODS get_def
      IMPORTING name          TYPE string
                syntax        TYPE string
      CHANGING  args          TYPE ty_t_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
      RAISING   zzxxmla1_cx_xmla.
    "! Resolver.resolve: found tells whether the arguments match.
    METHODS resolve
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion
      RAISING   zzxxmla1_cx_xmla.
    "! SimpleResolver and MultiResolver.resolve: the first signature the arguments convert to.
    METHODS resolve_by_signatures
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.
    "! SetFunDef.ResolverImpl: every argument a member, a tuple or a set.
    METHODS resolve_set
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.
    "! TupleFunDef.ResolverImpl: (x) for anything but a member, a tuple of members, or a crossjoin if a set is there.
    METHODS resolve_tuple
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.
    "! CrossJoinFunDef.ResolverImpl: two or more sets.
    METHODS resolve_crossjoin
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.
    "! OrderFunDef.ResolverImpl: a set, then one or more keys (a value, optionally followed by a symbol ASC, DESC, BASC
    "! or BDESC).
    METHODS resolve_order
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.
    "! SetItemFunDef's string resolver: &lt;Set&gt;.Item(&lt;String&gt; [, ...]), as many strings as the set's arity.
    METHODS resolve_set_item
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion
      RAISING   zzxxmla1_cx_xmla.
    "! CoalesceEmptyFunDef.ResolverImpl: all arguments numbers, else all strings.
    METHODS resolve_coalesce_empty
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.
    "! CaseTestFunDef.ResolverImpl (CASE WHEN c THEN x ... [ELSE y] END) and CaseMatchFunDef.ResolverImpl (CASE v WHEN m
    "! THEN x ... [ELSE y] END): the conditions logical (the matches of the value's category), the results of the
    "! category of the first result.
    METHODS resolve_case
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
                match       TYPE abap_bool
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.
    "! PropertiesFunDef.ResolverImpl: &lt;Member&gt;.Properties(&lt;String&gt;); the category of the property named by a
    "! literal (deducePropertyCategory: a member property of the last level of the member's hierarchy or of a level
    "! above it, else a standard property), else a value.
    METHODS resolve_properties
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
                conversions TYPE ty_t_conversion.
    "! The category of a standard member property (olap.Property: its type); a value for any other name.
    CLASS-METHODS property_category
      IMPORTING name          TYPE string
      RETURNING VALUE(result) TYPE i.
    "! CastFunDef.ResolverImpl: CAST(expression AS type), the type a literal STRING, NUMERIC, BOOLEAN or INTEGER.
    METHODS resolve_cast
      IMPORTING resolver    TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                args        TYPE ty_t_node
      EXPORTING fun_def     TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                found       TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! A function definition of the resolver; MultiResolver.createDummyFunDef gives it the arguments' categories.
    METHODS make_fun_def
      IMPORTING resolver        TYPE zzxxmla1_cl_mdx_funtable=>ty_resolver
                return_category TYPE i
                parameters      TYPE ty_t_category
                signature       TYPE ty_t_category OPTIONAL
                implementation  TYPE string OPTIONAL
      RETURNING VALUE(result)   TYPE zzxxmla1_cl_mdx_node=>ty_fun_def.
    "! TypeUtil.canConvert.
    METHODS can_convert
      IMPORTING ordinal       TYPE i
                from_type     TYPE ty_type
                to            TYPE i
      CHANGING  conversions   TYPE ty_t_conversion
      RETURNING VALUE(result) TYPE abap_bool.
    "! ValidatorImpl.requiresExpression: must the node being validated be a scalar expression?
    METHODS requires_expression
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS requires_expression_at
      IMPORTING position      TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
    "! Resolver.requiresExpression(k) of every resolver of the call.
    METHODS call_requires_expression
      IMPORTING call          TYPE ty_node
                k             TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
    "! FunDef.getResultType.
    METHODS result_type
      IMPORTING fun_def       TYPE zzxxmla1_cl_mdx_node=>ty_fun_def
                args          TYPE ty_t_node
      RETURNING VALUE(result) TYPE ty_type
      RAISING   zzxxmla1_cx_xmla.
    "! FunDefBase.castType.
    METHODS cast_type
      IMPORTING type          TYPE ty_type
                category      TYPE i
      RETURNING VALUE(result) TYPE ty_type.
    "! TypeUtil.toMemberType, toMemberOrTupleType with the dimension of a one-member tuple's hierarchy.
    METHODS to_member_type
      IMPORTING type          TYPE ty_type
      RETURNING VALUE(result) TYPE ty_type.
    METHODS to_member_or_tuple_type
      IMPORTING type          TYPE ty_type
      RETURNING VALUE(result) TYPE ty_type.
    "! CrossJoinFunDef.addTypes.
    METHODS add_types
      IMPORTING type  TYPE ty_type
      CHANGING  types TYPE zzxxmla1_cl_mdx_type=>ty_t_type
      RAISING   zzxxmla1_cx_xmla.
    "! TupleType.checkHierarchies.
    METHODS check_hierarchies
      IMPORTING types TYPE zzxxmla1_cl_mdx_type=>ty_t_type
      RAISING   zzxxmla1_cx_xmla.
    "! Exp.getCategory.
    METHODS category_of
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE i.
    "! Syntax.getSignature.
    CLASS-METHODS signature
      IMPORTING name            TYPE string
                syntax          TYPE string
                return_category TYPE i
                categories      TYPE ty_t_category
      RETURNING VALUE(result)   TYPE string.
    METHODS fail
      IMPORTING message TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! Formula.createElement: the calculated member the name of the formula defines, below the element named by the
    "! segments before the last one.
    METHODS create_formula_element
      IMPORTING formula       TYPE zzxxmla1_cl_mdx_parser=>ty_formula
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_schema_reader=>ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! Hierarchy.createMember: a calculated member named by the segment below the parent element.
    METHODS create_calculated_member
      IMPORTING parent        TYPE zzxxmla1_cl_mdx_schema_reader=>ty_element
                segment       TYPE zzxxmla1_cl_mdx_node=>ty_segment
                formula       TYPE zzxxmla1_cl_mdx_parser=>ty_formula
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_schema_reader=>ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! Formula.getSolveOrder: the SOLVE_ORDER property if it is a number or a negated number (quickEval), else 0.
    CLASS-METHODS solve_order_of
      IMPORTING formula       TYPE zzxxmla1_cl_mdx_parser=>ty_formula
      RETURNING VALUE(result) TYPE i.
    "! Formula.getFormatExp of the formula with the index: the FORMAT_STRING (or FORMAT) property, else for a decimal
    "! expression a pattern with its scale, else for a measure the format of the first member in the expression that has
    "! one (FormatFinder). Computed once; a formula whose format is being computed has none (a cycle).
    METHODS format_expression_of
      IMPORTING index         TYPE i
      RETURNING VALUE(result) TYPE ty_node.
    "! FormatFinder: the format of the first member of the expression that has one.
    METHODS find_format
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_node.
    "! RolapMemberBase.foundAggregateFunction: whether the expression calls Aggregate.
    CLASS-METHODS contains_aggregate
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool.

    "! the formulas of the query and the unique names of their members, while they are resolved
    DATA formulas        TYPE zzxxmla1_cl_mdx_parser=>ty_t_formula.
    DATA formula_members TYPE string_table.
    "! the state of each formula's format: empty (not computed), BUSY or DONE
    DATA format_states   TYPE string_table.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_validator IMPLEMENTATION.

  METHOD constructor.
    me->schema_reader = schema_reader.
    funtable = zzxxmla1_cl_mdx_funtable=>instance( ).
  ENDMETHOD.

  METHOD resolve_query.
    " createFormulaElements: all calculated members first, so that the formulas may refer to each other
    LOOP AT query-formulas INTO DATA(formula).
      IF formula-is_member = abap_false.
        " Formula.createElement: a SetBase named by the one segment
        IF lines( formula-name->segments ) <> 1.
          " Util.assertTrue
          fail( `Internal error: assert failed: set names must not be compound` ).
        ELSEIF formula-name->segments[ 1 ]-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
          fail( `Calculated member name must not contain member keys` ).
        ENDIF.
        APPEND VALUE #( name = formula-name->segments[ 1 ]-name key = |SET{ sy-tabix }|
                        expression = formula-expression ) TO named_sets.
        APPEND `` TO formula_members.
        APPEND `` TO format_states.
        CONTINUE.
      ENDIF.
      DATA(member) = create_formula_element( formula ).
      schema_reader->add_calculated_member( member ).
      APPEND member-unique_name TO formula_members.
      APPEND `` TO format_states.
    ENDLOOP.
    " the aliases (expression AS name) anywhere in the query
    LOOP AT query-formulas INTO formula.
      register_aliases( formula-expression ).
    ENDLOOP.
    LOOP AT query-axes INTO DATA(query_axis).
      register_aliases( query_axis-expression ).
    ENDLOOP.
    register_aliases( query-slicer ).

    " Formula.accept: the expression (a value, not a set) and the properties, then the formats; a named set's
    " expression must be a set
    LOOP AT query-formulas ASSIGNING FIELD-SYMBOL(<formula>).
      DATA(index) = sy-tabix.
      IF <formula>-is_member = abap_false.
        DATA(set_node) = named_set_expression( line_index( named_sets[ key = |SET{ index }| ] ) ).
        <formula>-expression = set_node->set_expression.
        IF <formula>-expression->get_type( )->is_set( ) = abap_false.
          fail( |Set expression '{ <formula>-name->unparse( ) }' must be a set| ).
        ENDIF.
        CONTINUE.
      ENDIF.
      <formula>-expression = validate( node = <formula>-expression scalar = abap_true ).
      LOOP AT <formula>-properties ASSIGNING FIELD-SYMBOL(<property>).
        <property>-expression = validate( <property>-expression ).
      ENDLOOP.
      DATA(calculated) = schema_reader->get_calculated_member( formula_members[ index ] ).
      calculated-expression = <formula>-expression.
      calculated-contains_aggregate = contains_aggregate( <formula>-expression ).
      schema_reader->set_calculated_member( calculated ).
    ENDLOOP.
    formulas = query-formulas.
    LOOP AT formulas INTO formula WHERE is_member = abap_true.
      DATA(formula_index) = sy-tabix.
      format_expression_of( formula_index ).
    ENDLOOP.

    " the axes of the subselects, resolved as the reference server resolves them for its subcube predicate
    " (Query.getSubcubePredicates): only their form is used, by the engine
    LOOP AT query-subcubes ASSIGNING FIELD-SYMBOL(<subcube>).
      LOOP AT <subcube>-axes ASSIGNING FIELD-SYMBOL(<subcube_axis>).
        APPEND VALUE #( kind = `AXIS` ) TO stack.
        TRY.
            <subcube_axis>-expression = validate( <subcube_axis>-expression ).
          CLEANUP.
            DELETE stack INDEX lines( stack ).
        ENDTRY.
        DELETE stack INDEX lines( stack ).
      ENDLOOP.
    ENDLOOP.

    " the axes: each one once, and 0 to n - 1 for n axes
    DATA used TYPE HASHED TABLE OF i WITH UNIQUE KEY table_line.
    LOOP AT query-axes ASSIGNING FIELD-SYMBOL(<axis>).
      resolve_axis( EXPORTING axis_name = zzxxmla1_cl_mdx_parser=>axis_name( <axis>-ordinal )
                    CHANGING expression = <axis>-expression ).
      INSERT <axis>-ordinal INTO TABLE used.
      IF sy-subrc <> 0.
        fail( |Duplicate axis name '{ zzxxmla1_cl_mdx_parser=>axis_name( <axis>-ordinal ) }'.| ).
      ENDIF.
    ENDLOOP.
    DO lines( query-axes ) TIMES.
      DATA(seek) = sy-index - 1.
      IF NOT line_exists( used[ table_line = seek ] ).
        fail( |Axis numbers specified in a query must be sequentially specified, and cannot contain gaps. |
           && |Axis { zzxxmla1_cl_mdx_format=>format( value = CONV #( seek ) pattern = `#,##0` ) } |
           && |({ zzxxmla1_cl_mdx_parser=>axis_name( seek ) }) is missing.| ).
      ENDIF.
    ENDDO.
    IF query-slicer IS BOUND.
      resolve_axis( EXPORTING axis_name = `SLICER` CHANGING expression = query-slicer ).
    ENDIF.

    " no hierarchy definitely on more than one axis
    DATA(all_axes) = VALUE ty_t_node( FOR axis IN query-axes ( axis-expression ) ).
    IF query-slicer IS BOUND.
      APPEND query-slicer TO all_axes.
    ENDIF.
    LOOP AT schema_reader->get_hierarchies( ) INTO DATA(hierarchy).
      DATA(count) = 0.
      LOOP AT all_axes INTO DATA(set).
        IF set->get_type( )->uses_hierarchy( hierarchy = hierarchy-id dimension_of_hierarchy = hierarchy-dimension
                                             definitely = abap_true ) = abap_true.
          count = count + 1.
        ENDIF.
      ENDLOOP.
      IF count > 1.
        fail( |Hierarchy '{ hierarchy-unique_name }' appears in more than one independent axis.| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD resolve_axis.
    APPEND VALUE #( kind = `AXIS` ) TO stack.
    TRY.
        expression = validate( expression ).
        DATA(type) = expression->get_type( ).
        IF type->is_set( ) = abap_false.
          IF type->kind = zzxxmla1_cl_mdx_type=>c_kind-member OR type->kind = zzxxmla1_cl_mdx_type=>c_kind-tuple
              OR type->kind = zzxxmla1_cl_mdx_type=>c_kind-dimension
              OR type->kind = zzxxmla1_cl_mdx_type=>c_kind-hierarchy.
            expression = validate( zzxxmla1_cl_mdx_node=>create_call(
                                     name = `{}` syntax = zzxxmla1_cl_mdx_node=>c_syntax-braces
                                     args = VALUE #( ( expression ) ) ) ).
          ELSE.
            fail( |Axis '{ axis_name }' expression is not a set| ).
          ENDIF.
        ENDIF.
      CLEANUP.
        DELETE stack INDEX lines( stack ).
    ENDTRY.
    DELETE stack INDEX lines( stack ).
  ENDMETHOD.

  METHOD validate.
    READ TABLE resolved_nodes WITH TABLE KEY node = node INTO DATA(known).
    IF sy-subrc = 0.
      IF known-resolved IS NOT BOUND.
        fail( |Infinite recursion encountered while validating '{ node->unparse( ) }'| ).
      ENDIF.
      result = known-resolved.
    ELSE.
      APPEND VALUE #( kind = `NODE` node = node ) TO stack.
      " a placeholder against recursion while the node is resolved
      INSERT VALUE #( node = node ) INTO TABLE resolved_nodes.
      TRY.
          result = accept( node ).
        CLEANUP.
          DELETE stack INDEX lines( stack ).
          DELETE TABLE resolved_nodes WITH TABLE KEY node = node.
      ENDTRY.
      DELETE stack INDEX lines( stack ).
      resolved_nodes[ node = node ]-resolved = result.
    ENDIF.

    IF scalar = abap_true AND result->get_type( )->can_evaluate( ) = abap_false.
      fail( |Member expression '{ result->unparse( ) }' must not be a set| ).
    ENDIF.
  ENDMETHOD.

  METHOD accept.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-id.
        result = validate_id( node ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-call.
        result = validate_call( node ).
      WHEN OTHERS.
        " literals and resolved expressions are resolved already
        result = node.
    ENDCASE.
  ENDMETHOD.

  METHOD validate_id.
    IF lines( node->segments ) = 1 AND node->segments[ 1 ]-quoting = zzxxmla1_cl_mdx_node=>c_quoting-unquoted
        AND funtable->is_reserved( node->segments[ 1 ]-name ) = abap_true.
      result = zzxxmla1_cl_mdx_node=>create_symbol( to_upper( node->segments[ 1 ]-name ) ).
      RETURN.
    ENDIF.
    " the aliases in scope first (ScopedSchemaReader), then the cube, then the named sets of the query
    DATA(set_index) = lookup_alias( node->segments ).
    IF set_index > 0.
      result = named_set_expression( set_index ).
      RETURN.
    ENDIF.
    result = lookup_property_reference( node ).
    IF result IS BOUND.
      RETURN.
    ENDIF.
    DATA(element) = schema_reader->lookup_compound( node->segments ).
    IF element-kind IS INITIAL.
      set_index = lookup_query_set( node->segments ).
      IF set_index > 0.
        result = named_set_expression( set_index ).
        RETURN.
      ENDIF.
      fail( |MDX object '{ node->unparse( ) }' not found in cube '{ schema_reader->cube-cube_name }'| ).
    ENDIF.
    result = element_expression( element ).
  ENDMETHOD.

  METHOD lookup_property_reference.
    DATA(count) = lines( node->segments ).
    IF count < 2 OR node->segments[ count ]-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
      RETURN.
    ENDIF.
    DATA(name) = node->segments[ count ]-name.
    DATA(segments) = node->segments.
    DELETE segments INDEX count.
    DATA(member) = schema_reader->lookup_compound( segments = segments
                                                   category = zzxxmla1_cl_mdx_type=>c_category-member ).
    DATA(level) = 0.
    IF member-kind = zzxxmla1_cl_mdx_schema_reader=>c_element-member.
      level = member-member-level.
    ENDIF.
    IF level = 0 OR schema_reader->is_valid_property( level = level name = name ) = abap_false.
      DATA(element) = schema_reader->lookup_compound( segments = segments
                                                      category = zzxxmla1_cl_mdx_type=>c_category-level ).
      IF element-kind <> zzxxmla1_cl_mdx_schema_reader=>c_element-level
          OR schema_reader->is_valid_property( level = element-id name = name ) = abap_false.
        RETURN.
      ENDIF.
    ENDIF.
    result = validate( zzxxmla1_cl_mdx_node=>create_call(
                         name   = name
                         syntax = zzxxmla1_cl_mdx_node=>c_syntax-property
                         args   = VALUE #( ( zzxxmla1_cl_mdx_node=>create_id( segments ) ) ) ) ).
  ENDMETHOD.

  METHOD element_expression.
    CASE element-kind.
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-member.
        DATA(hierarchy) = element-member-hier_id.
        result = zzxxmla1_cl_mdx_node=>create_element(
                   kind = zzxxmla1_cl_mdx_node=>c_kind-member element = element name = element-member-unique_name
                   type = zzxxmla1_cl_mdx_type=>member_type( dimension = schema_reader->dimension_of( hierarchy )
                                                             hierarchy = hierarchy level = element-member-level
                                                             member = element-member-unique_name ) ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-level.
        DATA(level) = schema_reader->get_level( element-id ).
        result = zzxxmla1_cl_mdx_node=>create_element(
                   kind = zzxxmla1_cl_mdx_node=>c_kind-level element = element name = level-unique_name
                   type = zzxxmla1_cl_mdx_type=>level_type( dimension = schema_reader->dimension_of( level-hierarchy )
                                                            hierarchy = level-hierarchy level = level-id ) ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-hierarchy.
        result = zzxxmla1_cl_mdx_node=>create_element(
                   kind = zzxxmla1_cl_mdx_node=>c_kind-hierarchy element = element
                   name = schema_reader->get_hierarchy( element-id )-unique_name
                   type = zzxxmla1_cl_mdx_type=>hierarchy_type( dimension = schema_reader->dimension_of( element-id )
                                                                hierarchy = element-id ) ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-dimension.
        result = zzxxmla1_cl_mdx_node=>create_element(
                   kind = zzxxmla1_cl_mdx_node=>c_kind-dimension element = element
                   name = schema_reader->get_dimension( element-id )-unique_name
                   type = zzxxmla1_cl_mdx_type=>dimension_type(
                            dimension = element-id
                            hierarchy = schema_reader->get_dimension_hierarchy( element-id ) ) ).
    ENDCASE.
  ENDMETHOD.

  METHOD validate_call.
    DATA args TYPE ty_t_node.
    LOOP AT node->args INTO DATA(arg).
      APPEND validate( arg ) TO args.
    ENDLOOP.
    DATA(fun_def) = get_def( EXPORTING name = node->name syntax = node->syntax CHANGING args = args ).
    " NamedSetCurrentFunDef, NamedSetCurrentOrdinalFunDef: createCall
    IF ( to_upper( fun_def-name ) = `CURRENT` OR to_upper( fun_def-name ) = `CURRENTORDINAL` )
        AND fun_def-syntax = zzxxmla1_cl_mdx_node=>c_syntax-property
        AND args[ 1 ]->kind <> zzxxmla1_cl_mdx_node=>c_kind-named_set.
      fail( `Not a named set` ).
    ENDIF.
    result = zzxxmla1_cl_mdx_node=>create_resolved_call( fun_def = fun_def args = args
                                                         type = result_type( fun_def = fun_def args = args ) ).
  ENDMETHOD.

  METHOD get_def.
    DATA(categories) = VALUE ty_t_category( FOR arg IN args ( category_of( arg ) ) ).
    DATA(text) = signature( name = name syntax = syntax return_category = c_category-unknown categories = categories ).

    DATA matches TYPE STANDARD TABLE OF zzxxmla1_cl_mdx_node=>ty_fun_def WITH EMPTY KEY.
    DATA match_conversions TYPE ty_t_conversion.
    DATA(min_cost) = cl_abap_math=>max_int4.
    LOOP AT funtable->get_resolvers( name = name syntax = syntax ) INTO DATA(resolver).
      resolve( EXPORTING resolver = resolver args = args
               IMPORTING fun_def = DATA(fun_def) found = DATA(found) conversions = DATA(conversions) ).
      IF found = abap_false.
        CONTINUE.
      ENDIF.
      DATA(cost) = REDUCE i( INIT sum = 0 FOR conversion IN conversions NEXT sum = sum + conversion-cost ).
      IF cost < min_cost.
        min_cost = cost.
        matches = VALUE #( ( fun_def ) ).
        match_conversions = conversions.
      ELSEIF cost = min_cost.
        APPEND fun_def TO matches.
      ENDIF.
    ENDLOOP.
    CASE lines( matches ).
      WHEN 0.
        fail( |No function matches signature '{ text }'| ).
      WHEN 1.
      WHEN OTHERS.
        fail( |More than one function matches signature '{ text }'; they are: |
           && concat_lines_of( table = VALUE string_table( FOR match IN matches ( match-signature ) ) sep = `, ` ) ).
    ENDCASE.
    result = matches[ 1 ].

    " a member or tuple where a set is wanted is put in braces
    LOOP AT match_conversions INTO DATA(applied)
         WHERE ( from = c_category-member OR from = c_category-tuple ) AND to = c_category-set.
      args[ applied-ordinal + 1 ] = validate( zzxxmla1_cl_mdx_node=>create_call(
                                                name = `{}` syntax = zzxxmla1_cl_mdx_node=>c_syntax-braces
                                                args = VALUE #( ( args[ applied-ordinal + 1 ] ) ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD resolve.
    CLEAR: fun_def, found, conversions.
    CASE resolver-kind.
      WHEN `SetFunDef$ResolverImpl`.
        resolve_set( EXPORTING resolver = resolver args = args
                     IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN `TupleFunDef$ResolverImpl`.
        resolve_tuple( EXPORTING resolver = resolver args = args
                       IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN `CrossJoinFunDef$ResolverImpl`.
        resolve_crossjoin( EXPORTING resolver = resolver args = args
                           IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN `CrossJoinFunDef$StarCrossJoinResolver`.
        " * is a crossjoin only where a set may stand
        IF requires_expression( ) = abap_false.
          resolve_by_signatures( EXPORTING resolver = resolver args = args
                                 IMPORTING fun_def = fun_def found = found conversions = conversions ).
          fun_def-implementation = `CrossJoinFunDef`.
        ENDIF.
      WHEN `OrderFunDef$ResolverImpl`.
        resolve_order( EXPORTING resolver = resolver args = args
                       IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN `CastFunDef$ResolverImpl`.
        resolve_cast( EXPORTING resolver = resolver args = args IMPORTING fun_def = fun_def found = found ).
      WHEN `AsFunDef$ResolverImpl`.
        resolve_as( EXPORTING resolver = resolver args = args
                    IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN `CoalesceEmptyFunDef$ResolverImpl`.
        resolve_coalesce_empty( EXPORTING resolver = resolver args = args
                                IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN `CaseTestFunDef$ResolverImpl` OR `CaseMatchFunDef$ResolverImpl`.
        resolve_case( EXPORTING resolver = resolver args = args
                                match = xsdbool( resolver-kind = `CaseMatchFunDef$ResolverImpl` )
                      IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN `PropertiesFunDef$ResolverImpl`.
        resolve_properties( EXPORTING resolver = resolver args = args
                            IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN `CacheFunDef$CacheFunResolver` OR `ExtractFunDef$1`
          OR `StrToSetFunDef$ResolverImpl` OR `StrToTupleFunDef$ResolverImpl`.
        fail( |The function { resolver-signature_text } is not implemented yet| ).
      WHEN `SetItemFunDef$1`.
        resolve_set_item( EXPORTING resolver = resolver args = args
                          IMPORTING fun_def = fun_def found = found conversions = conversions ).
      WHEN OTHERS.
        resolve_by_signatures( EXPORTING resolver = resolver args = args
                               IMPORTING fun_def = fun_def found = found conversions = conversions ).
        IF found = abap_true AND to_upper( resolver-name ) = `NONEMPTYCROSSJOIN`.
          " NonEmptyCrossJoinFunDef extends CrossJoinFunDef
          fun_def-implementation = `NonEmptyCrossJoinFunDef`.
        ELSEIF found = abap_true AND to_upper( resolver-name ) = `ITEM`
            AND fun_def-signature_categories[ 1 ] = c_category-set.
          " <Set>.Item(<Index>): its type is the set's element type
          fun_def-implementation = `SetItemFunDef`.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD resolve_by_signatures.
    CLEAR: fun_def, found, conversions.
    LOOP AT resolver-signatures INTO DATA(signature).
      IF lines( signature-parameter_categories ) <> lines( args ).
        CONTINUE.
      ENDIF.
      CLEAR conversions.
      found = abap_true.
      LOOP AT args INTO DATA(arg).
        IF can_convert( EXPORTING ordinal = sy-tabix - 1 from_type = arg->get_type( )
                                  to = signature-parameter_categories[ sy-tabix ]
                        CHANGING conversions = conversions ) = abap_false.
          found = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF found = abap_true.
        " a SimpleResolver's FunDef has the signature's parameters (a UdfResolver's UdfFunDef those of the user-defined
        " function), a MultiResolver's those of the arguments
        DATA(parameters) = COND ty_t_category( WHEN resolver-kind = `SimpleResolver` OR resolver-kind = `UdfResolver`
                                               THEN signature-parameter_categories
                                               ELSE VALUE #( FOR a IN args ( category_of( a ) ) ) ).
        fun_def = make_fun_def( resolver = resolver return_category = signature-return_category
                                parameters = parameters signature = signature-parameter_categories ).
        RETURN.
      ENDIF.
    ENDLOOP.
    CLEAR conversions.
  ENDMETHOD.

  METHOD resolve_set.
    CLEAR: fun_def, found, conversions.
    DATA parameters TYPE ty_t_category.
    LOOP AT args INTO DATA(arg).
      DATA(ordinal) = sy-tabix - 1.
      DATA(type) = arg->get_type( ).
      IF can_convert( EXPORTING ordinal = ordinal from_type = type to = c_category-member CHANGING conversions = conversions ) = abap_true.
        APPEND c_category-member TO parameters.
      ELSEIF can_convert( EXPORTING ordinal = ordinal from_type = type to = c_category-tuple CHANGING conversions = conversions ) = abap_true.
        APPEND c_category-tuple TO parameters.
      ELSEIF can_convert( EXPORTING ordinal = ordinal from_type = type to = c_category-set CHANGING conversions = conversions ) = abap_true.
        APPEND c_category-set TO parameters.
      ELSE.
        CLEAR conversions.
        RETURN.
      ENDIF.
    ENDLOOP.
    found = abap_true.
    fun_def = make_fun_def( resolver = resolver return_category = c_category-set parameters = parameters
                            implementation = `SetFunDef` ).
  ENDMETHOD.

  METHOD resolve_tuple.
    CLEAR: fun_def, found, conversions.
    IF lines( args ) = 1 AND args[ 1 ]->get_type( )->kind <> zzxxmla1_cl_mdx_type=>c_kind-member.
      " (x) of anything but a member is x
      DATA(category) = category_of( args[ 1 ] ).
      found = abap_true.
      fun_def = make_fun_def( resolver = resolver return_category = category parameters = VALUE #( ( category ) )
                              implementation = `ParenthesesFunDef` ).
      RETURN.
    ENDIF.
    DATA parameters TYPE ty_t_category.
    DATA(has_set) = abap_false.
    LOOP AT args INTO DATA(arg).
      DATA(ordinal) = sy-tabix - 1.
      IF can_convert( EXPORTING ordinal = ordinal from_type = arg->get_type( ) to = c_category-member CHANGING conversions = conversions ) = abap_true.
        APPEND c_category-member TO parameters.
      ELSEIF can_convert( EXPORTING ordinal = ordinal from_type = arg->get_type( ) to = c_category-set CHANGING conversions = conversions ) = abap_true.
        has_set = abap_true.
        APPEND c_category-set TO parameters.
      ELSE.
        CLEAR conversions.
        RETURN.
      ENDIF.
    ENDLOOP.
    found = abap_true.
    IF has_set = abap_true.
      fun_def = make_fun_def( resolver = resolver return_category = c_category-set
                              parameters = VALUE #( FOR a IN args ( category_of( a ) ) )
                              implementation = `CrossJoinFunDef` ).
    ELSE.
      fun_def = make_fun_def( resolver = resolver return_category = c_category-tuple parameters = parameters
                              implementation = `TupleFunDef` ).
    ENDIF.
  ENDMETHOD.

  METHOD resolve_crossjoin.
    CLEAR: fun_def, found, conversions.
    IF lines( args ) < 2.
      RETURN.
    ENDIF.
    LOOP AT args INTO DATA(arg).
      IF can_convert( EXPORTING ordinal = sy-tabix - 1 from_type = arg->get_type( ) to = c_category-set
                      CHANGING conversions = conversions ) = abap_false.
        CLEAR conversions.
        RETURN.
      ENDIF.
    ENDLOOP.
    found = abap_true.
    fun_def = make_fun_def( resolver = resolver return_category = c_category-set
                            parameters = VALUE #( FOR a IN args ( category_of( a ) ) ) implementation = `CrossJoinFunDef` ).
  ENDMETHOD.

  METHOD resolve_order.
    CLEAR: fun_def, found, conversions.
    IF lines( args ) < 2.
      RETURN.
    ENDIF.
    IF can_convert( EXPORTING ordinal = 0 from_type = args[ 1 ]->get_type( ) to = c_category-set
                    CHANGING conversions = conversions ) = abap_false.
      CLEAR conversions.
      RETURN.
    ENDIF.
    DATA(parameters) = VALUE ty_t_category( ( c_category-set ) ).
    " then value [, symbol] for each key; a key without a symbol is ASC
    DATA(i) = 2.
    WHILE i <= lines( args ).
      IF can_convert( EXPORTING ordinal = i - 1 from_type = args[ i ]->get_type( ) to = c_category-value
                      CHANGING conversions = conversions ) = abap_false.
        CLEAR conversions.
        RETURN.
      ENDIF.
      APPEND c_category-value TO parameters.
      i = i + 1.
      IF i <= lines( args ) AND can_convert( EXPORTING ordinal = i - 1 from_type = args[ i ]->get_type( )
                                                       to = c_category-symbol
                                             CHANGING conversions = conversions ) = abap_true.
        APPEND c_category-symbol TO parameters.
        i = i + 1.
      ENDIF.
    ENDWHILE.
    found = abap_true.
    fun_def = make_fun_def( resolver = resolver return_category = c_category-set parameters = parameters
                            implementation = `OrderFunDef` ).
  ENDMETHOD.

  METHOD register_aliases.
    IF node IS NOT BOUND OR node->kind <> zzxxmla1_cl_mdx_node=>c_kind-call.
      RETURN.
    ENDIF.
    LOOP AT node->args INTO DATA(arg).
      IF arg->kind = zzxxmla1_cl_mdx_node=>c_kind-call AND arg->syntax = zzxxmla1_cl_mdx_node=>c_syntax-infix
          AND to_upper( arg->name ) = `AS` AND lines( arg->args ) = 2
          AND arg->args[ 2 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-id.
        APPEND VALUE #( name = arg->args[ 2 ]->segments[ 1 ]-name key = |ALIAS{ lines( named_sets ) + 1 }|
                        dynamic = abap_true scope = node expression = arg->args[ 1 ] ) TO named_sets.
      ENDIF.
      register_aliases( arg ).
    ENDLOOP.
  ENDMETHOD.

  METHOD lookup_alias.
    IF lines( segments ) <> 1 OR segments[ 1 ]-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
      RETURN.
    ENDIF.
    DATA(best) = 0.
    LOOP AT named_sets INTO DATA(named_set) WHERE dynamic = abap_true.
      DATA(index) = sy-tabix.
      " Util.equalName, not case-sensitive
      IF to_upper( named_set-name ) <> to_upper( segments[ 1 ]-name ).
        CONTINUE.
      ENDIF.
      LOOP AT stack INTO DATA(frame).
        IF frame-node = named_set-scope.
          IF sy-tabix > best.
            best = sy-tabix.
            result = index.
          ENDIF.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD lookup_query_set.
    IF lines( segments ) <> 1 OR segments[ 1 ]-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
      RETURN.
    ENDIF.
    " the name as written (lookupNamedSet: String.equals)
    LOOP AT named_sets INTO DATA(named_set) WHERE dynamic = abap_false AND name = segments[ 1 ]-name.
      result = sy-tabix.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD named_set_expression.
    DATA(named_set) = named_sets[ index ].
    IF named_set-node IS BOUND.
      result = named_set-node.
      RETURN.
    ENDIF.
    IF named_set-busy = abap_true.
      " a set that refers to itself: its expression has no type yet, so it converts to nothing (the reference: "No function
      " matches signature" of the call around the reference)
      result = zzxxmla1_cl_mdx_node=>create_named_set(
                 name = COND #( WHEN named_set-dynamic = abap_true THEN named_set-name ELSE |[{ named_set-name }]| )
                 key = named_set-key expression = named_set-expression dynamic = named_set-dynamic
                 type = zzxxmla1_cl_mdx_type=>cube( ) ).
      RETURN.
    ENDIF.
    named_sets[ index ]-busy = abap_true.
    TRY.
        DATA(expression) = validate( named_set-expression ).
      CLEANUP.
        named_sets[ index ]-busy = abap_false.
    ENDTRY.
    named_sets[ index ]-busy = abap_false.
    DATA(type) = expression->get_type( ).
    IF type->kind = zzxxmla1_cl_mdx_type=>c_kind-member OR type->kind = zzxxmla1_cl_mdx_type=>c_kind-tuple.
      IF named_set-dynamic = abap_true.
        expression = validate( zzxxmla1_cl_mdx_node=>create_call( name = `{}` syntax = zzxxmla1_cl_mdx_node=>c_syntax-braces
                                                                  args = VALUE #( ( expression ) ) ) ).
        type = expression->get_type( ).
      ELSE.
        type = zzxxmla1_cl_mdx_type=>set_type( type ).
      ENDIF.
    ENDIF.
    " the unique name: [name] of a SetBase, the name of an alias
    result = zzxxmla1_cl_mdx_node=>create_named_set(
               name = COND #( WHEN named_set-dynamic = abap_true THEN named_set-name ELSE |[{ named_set-name }]| )
               key = named_set-key expression = expression dynamic = named_set-dynamic type = type ).
    named_sets[ index ]-node = result.
  ENDMETHOD.

  METHOD resolve_as.
    CLEAR: fun_def, found, conversions.
    IF lines( args ) <> 2 OR args[ 2 ]->kind <> zzxxmla1_cl_mdx_node=>c_kind-named_set
        OR can_convert( EXPORTING ordinal = 0 from_type = args[ 1 ]->get_type( ) to = c_category-set
                        CHANGING conversions = conversions ) = abap_false.
      CLEAR conversions.
      RETURN.
    ENDIF.
    found = abap_true.
    fun_def = make_fun_def( resolver = resolver return_category = c_category-set
                            parameters = VALUE #( FOR arg IN args ( category_of( arg ) ) )
                            implementation = `AsFunDef` ).
  ENDMETHOD.

  METHOD resolve_set_item.
    CLEAR: fun_def, found, conversions.
    IF args IS INITIAL OR args[ 1 ]->get_type( )->kind <> zzxxmla1_cl_mdx_type=>c_kind-set.
      RETURN.
    ENDIF.
    DATA(arity) = args[ 1 ]->get_type( )->get_arity( ).
    LOOP AT args INTO DATA(arg) FROM 2.
      IF can_convert( EXPORTING ordinal = sy-tabix - 1 from_type = arg->get_type( ) to = c_category-string
                      CHANGING conversions = conversions ) = abap_false.
        CLEAR conversions.
        RETURN.
      ENDIF.
    ENDLOOP.
    IF lines( args ) - 1 <> arity.
      fail( |Argument count does not match set's cardinality { arity }| ).
    ENDIF.
    found = abap_true.
    fun_def = make_fun_def( resolver = resolver
                            return_category = COND #( WHEN arity = 1 THEN c_category-member ELSE c_category-tuple )
                            parameters = VALUE #( FOR a IN args ( category_of( a ) ) )
                            implementation = `SetItemFunDef` ).
  ENDMETHOD.

  METHOD resolve_coalesce_empty.
    CLEAR: fun_def, found, conversions.
    IF args IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT VALUE ty_t_category( ( c_category-numeric ) ( c_category-string ) ) INTO DATA(category).
      CLEAR conversions.
      DATA(matching) = 0.
      LOOP AT args INTO DATA(arg).
        IF can_convert( EXPORTING ordinal = sy-tabix - 1 from_type = arg->get_type( ) to = category
                        CHANGING conversions = conversions ) = abap_true.
          matching = matching + 1.
        ENDIF.
      ENDLOOP.
      IF matching = lines( args ).
        found = abap_true.
        DATA(parameters) = VALUE ty_t_category( FOR a IN args ( category ) ).
        fun_def = make_fun_def( resolver = resolver return_category = category parameters = parameters
                                signature = parameters implementation = `CoalesceEmptyFunDef` ).
        RETURN.
      ENDIF.
    ENDLOOP.
    CLEAR conversions.
  ENDMETHOD.

  METHOD resolve_case.
    CLEAR: fun_def, found, conversions.
    IF ( match = abap_true AND lines( args ) < 3 ) OR ( match = abap_false AND lines( args ) < 2 ).
      RETURN.
    ENDIF.
    " the value (CaseMatch), then pairs of condition or match and result, then the default
    DATA(value_category) = COND i( WHEN match = abap_true THEN category_of( args[ 1 ] ) ELSE c_category-logical ).
    DATA(first) = COND i( WHEN match = abap_true THEN 2 ELSE 1 ).
    DATA(return_category) = category_of( args[ first + 1 ] ).
    DATA(mismatching) = 0.
    LOOP AT args INTO DATA(arg).
      DATA(position) = sy-tabix.
      DATA(category) = COND i( WHEN position < first THEN value_category
                               WHEN position = lines( args ) AND ( position - first ) MOD 2 = 0 THEN return_category
                               WHEN ( position - first ) MOD 2 = 0 THEN value_category
                               ELSE return_category ).
      IF can_convert( EXPORTING ordinal = position - 1 from_type = arg->get_type( ) to = category
                      CHANGING conversions = conversions ) = abap_false.
        mismatching = mismatching + 1.
      ENDIF.
    ENDLOOP.
    IF mismatching > 0.
      CLEAR conversions.
      RETURN.
    ENDIF.
    found = abap_true.
    fun_def = make_fun_def( resolver = resolver return_category = return_category
                            parameters = VALUE #( FOR a IN args ( category_of( a ) ) )
                            implementation = COND #( WHEN match = abap_true THEN `CaseMatchFunDef`
                                                     ELSE `CaseTestFunDef` ) ).
  ENDMETHOD.

  METHOD resolve_properties.
    CLEAR: fun_def, found, conversions.
    IF lines( args ) <> 2
        OR can_convert( EXPORTING ordinal = 0 from_type = args[ 1 ]->get_type( ) to = c_category-member
                        CHANGING conversions = conversions ) = abap_false
        OR can_convert( EXPORTING ordinal = 1 from_type = args[ 2 ]->get_type( ) to = c_category-string
                        CHANGING conversions = conversions ) = abap_false.
      CLEAR conversions.
      RETURN.
    ENDIF.
    DATA(return_category) = c_category-value.
    DATA(hierarchy) = args[ 1 ]->get_type( )->get_hierarchy( ).
    IF args[ 2 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-literal
        AND args[ 2 ]->category = zzxxmla1_cl_mdx_node=>c_category-string
        AND hierarchy <> zzxxmla1_cl_mdx_type=>c_none.
      DATA(levels) = schema_reader->get_hierarchy( hierarchy )-levels.
      DATA(property) = schema_reader->lookup_level_property( level = levels[ lines( levels ) ]
                                                             name  = args[ 2 ]->value ).
      return_category = COND #( WHEN property IS INITIAL THEN property_category( args[ 2 ]->value )
                                WHEN property-data_type = `String` THEN c_category-string
                                WHEN property-data_type = `Boolean` THEN c_category-logical
                                ELSE c_category-numeric ).
    ENDIF.
    found = abap_true.
    DATA(parameters) = VALUE ty_t_category( ( c_category-member ) ( c_category-string ) ).
    fun_def = make_fun_def( resolver = resolver return_category = return_category parameters = parameters
                            signature = parameters implementation = `PropertiesFunDef` ).
  ENDMETHOD.

  METHOD property_category.
    CASE to_upper( name ).
      WHEN `NAME` OR `CAPTION` OR `CATALOG_NAME` OR `SCHEMA_NAME` OR `CUBE_NAME` OR `DIMENSION_UNIQUE_NAME`
        OR `HIERARCHY_UNIQUE_NAME` OR `LEVEL_UNIQUE_NAME` OR `LEVEL_NUMBER` OR `MEMBER_NAME` OR `MEMBER_UNIQUE_NAME`
        OR `MEMBER_GUID` OR `MEMBER_CAPTION` OR `PARENT_UNIQUE_NAME` OR `DESCRIPTION` OR `CELL_FORMATTER`
        OR `CELL_FORMATTER_SCRIPT_LANGUAGE` OR `CELL_FORMATTER_SCRIPT` OR `BACK_COLOR` OR `CELL_EVALUATION_LIST`
        OR `FORE_COLOR` OR `FONT_NAME` OR `FONT_SIZE` OR `FORMATTED_VALUE` OR `FORMAT_STRING` OR `NON_EMPTY_BEHAVIOR`
        OR `DATATYPE` OR `DISPLAY_FOLDER` OR `FORMAT_EXP`
        " KEY and MEMBER_KEY: the category of the level's data type, a string here
        OR `MEMBER_KEY` OR `KEY`.
        result = c_category-string.
      WHEN `MEMBER_ORDINAL` OR `MEMBER_TYPE` OR `CHILDREN_CARDINALITY` OR `PARENT_LEVEL` OR `PARENT_COUNT`
        OR `CELL_ORDINAL` OR `FONT_FLAGS` OR `SOLVE_ORDER` OR `VALUE` OR `DEPTH` OR `DISPLAY_INFO` OR `LANGUAGE`
        OR `ACTION_TYPE` OR `DRILLTHROUGH_COUNT`.
        result = c_category-numeric.
      WHEN `VISIBLE`.
        result = c_category-logical.
      WHEN OTHERS.
        result = c_category-value.
    ENDCASE.
  ENDMETHOD.

  METHOD resolve_cast.
    CLEAR: fun_def, found.
    IF lines( args ) <> 2 OR args[ 2 ]->kind <> zzxxmla1_cl_mdx_node=>c_kind-literal.
      RETURN.
    ENDIF.
    DATA(type_name) = args[ 2 ]->value.
    DATA(return_category) = SWITCH i( to_upper( type_name ) WHEN `STRING` THEN c_category-string
                                                            WHEN `NUMERIC` THEN c_category-numeric
                                                            WHEN `BOOLEAN` THEN c_category-logical
                                                            WHEN `INTEGER` THEN c_category-integer ).
    IF return_category = 0.
      fail( |Unknown type '{ type_name }'; values are NUMERIC, STRING, BOOLEAN| ).
    ENDIF.
    found = abap_true.
    fun_def = make_fun_def( resolver = resolver return_category = return_category
                            parameters = VALUE #( FOR arg IN args ( category_of( arg ) ) )
                            implementation = `CastFunDef` ).
  ENDMETHOD.

  METHOD make_fun_def.
    result = VALUE #( name = resolver-name syntax = resolver-syntax return_category = return_category
                      parameter_categories = parameters signature_categories = signature
                      resolver_kind = resolver-kind resolver_id = resolver-id implementation = implementation
                      signature = signature( name = resolver-name syntax = resolver-syntax
                                             return_category = return_category categories = parameters ) ).
  ENDMETHOD.

  METHOD can_convert.
    DATA(from) = from_type->category( ).
    IF from = to.
      result = abap_true.
      RETURN.
    ENDIF.
    DATA(cost) = 0.
    CASE from.
      WHEN c_category-dimension.
        " to a hierarchy (and from there to a member or tuple) via the default hierarchy
        cost = SWITCH #( to WHEN c_category-member OR c_category-tuple OR c_category-hierarchy THEN 2
                            WHEN c_category-level THEN 3 ).
      WHEN c_category-hierarchy.
        " an implicit CurrentMember: [Product].PrevMember is [Product].CurrentMember.PrevMember
        cost = SWITCH #( to WHEN c_category-dimension OR c_category-member OR c_category-tuple THEN 1 ).
      WHEN c_category-level.
        cost = SWITCH #( to WHEN c_category-dimension THEN 2 WHEN c_category-hierarchy OR c_category-set THEN 1 ).
      WHEN c_category-logical.
        result = xsdbool( to = c_category-value ).
        RETURN.
      WHEN c_category-member.
        IF from_type->get_dimension( ) = zzxxmla1_cl_mdx_schema_reader=>c_measures.
          cost = SWITCH #( to WHEN c_category-numeric THEN 1 WHEN c_category-value OR c_category-string THEN 2
                              WHEN c_category-dimension OR c_category-hierarchy OR c_category-level
                                   OR c_category-tuple THEN 3
                              WHEN c_category-set THEN 4 ).
        ELSE.
          cost = SWITCH #( to WHEN c_category-dimension OR c_category-hierarchy OR c_category-level
                                   OR c_category-tuple THEN 1
                              WHEN c_category-set THEN 2 WHEN c_category-numeric THEN 3
                              WHEN c_category-value OR c_category-string THEN 4 ).
        ENDIF.
      WHEN c_category-numeric.
        IF to = c_category-logical.
          cost = 2.
        ELSE.
          result = xsdbool( to = c_category-value OR to = c_category-integer
                            OR to = c_category-integer + c_category-constant
                            OR to = c_category-numeric + c_category-constant ).
          RETURN.
        ENDIF.
      WHEN c_category-integer.
        result = xsdbool( to = c_category-value OR to = c_category-integer + c_category-constant
                          OR to = c_category-numeric OR to = c_category-numeric + c_category-constant ).
        RETURN.
      WHEN c_category-string.
        result = xsdbool( to = c_category-value OR to = c_category-string + c_category-constant ).
        RETURN.
      WHEN c_category-datetime.
        result = xsdbool( to = c_category-value OR to = c_category-datetime + c_category-constant ).
        RETURN.
      WHEN c_category-tuple.
        cost = SWITCH #( to WHEN c_category-numeric THEN 3 WHEN c_category-set THEN 2
                            WHEN c_category-string OR c_category-value THEN 4 ).
      WHEN c_category-value.
        " a value can become a more specific scalar, at a significant cost
        cost = SWITCH #( to WHEN c_category-string OR c_category-numeric OR c_category-logical THEN 2 ).
      WHEN c_category-null.
        " null is a scalar, and a member at a cost
        IF to = c_category-value OR to = c_category-numeric OR to = c_category-string OR to = c_category-logical
            OR to = c_category-integer OR to = c_category-datetime OR to = c_category-symbol.
          result = abap_true.
          RETURN.
        ENDIF.
        cost = COND #( WHEN to = c_category-member THEN 2 ).
      WHEN OTHERS.
        " array, set, symbol, empty
        RETURN.
    ENDCASE.
    IF cost > 0.
      APPEND VALUE #( from = from to = to ordinal = ordinal cost = cost ) TO conversions.
      result = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD requires_expression.
    result = requires_expression_at( lines( stack ) ).
  ENDMETHOD.

  METHOD requires_expression_at.
    IF position < 2.
      RETURN.
    ENDIF.
    DATA(parent) = stack[ position - 1 ].
    IF parent-kind <> `NODE`.
      " an axis takes a set
      RETURN.
    ENDIF.
    DATA(call) = parent-node.
    IF call->kind <> zzxxmla1_cl_mdx_node=>c_kind-call AND call->kind <> zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      RETURN.
    ENDIF.
    IF call->syntax = zzxxmla1_cl_mdx_node=>c_syntax-parentheses OR
        ( call->kind = zzxxmla1_cl_mdx_node=>c_kind-call AND call->name = `*` ).
      result = requires_expression_at( position - 1 ).
      RETURN.
    ENDIF.
    DATA(child) = stack[ position ]-node.
    DATA(k) = -1.
    LOOP AT call->args INTO DATA(arg).
      IF arg = child.
        k = sy-tabix - 1.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF k < 0.
      RETURN.
    ENDIF.
    IF call->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      result = xsdbool( call->fun_def-parameter_categories[ k + 1 ] <> c_category-set ).
    ELSE.
      result = call_requires_expression( call = call k = k ).
    ENDIF.
  ENDMETHOD.

  METHOD call_requires_expression.
    " the call has not been resolved yet; a scalar is required only if no resolver accepts a set at k
    result = abap_true.
    LOOP AT funtable->get_resolvers( name = call->name syntax = call->syntax ) INTO DATA(resolver).
      DATA(requires) = abap_true.
      IF resolver-kind = `SimpleResolver`.
        IF lines( resolver-signatures ) > 0 AND k < lines( resolver-signatures[ 1 ]-parameter_categories ).
          requires = xsdbool( resolver-signatures[ 1 ]-parameter_categories[ k + 1 ] <> c_category-set ).
        ENDIF.
      ELSEIF resolver-kind CP `*$ResolverImpl` AND resolver-kind NP `AddCalculatedMembers*`
          AND resolver-kind NP `TopBottomPercentSum*` AND resolver-kind NP `Xtd*`
          AND resolver-kind <> `CoalesceEmptyFunDef$ResolverImpl` AND resolver-kind <> `CaseTestFunDef$ResolverImpl`
          AND resolver-kind <> `CaseMatchFunDef$ResolverImpl` AND resolver-kind <> `PropertiesFunDef$ResolverImpl`
          OR resolver-kind = `CacheFunDef$CacheFunResolver` OR resolver-kind = `ExtractFunDef$1`
          OR resolver-kind = `SetItemFunDef$1` OR resolver-kind = `UdfResolver`.
        " ResolverBase.requiresExpression is false (CoalesceEmpty, CASE and Properties require expressions)
        requires = abap_false.
      ELSE.
        " MultiResolver: false if a signature has a set at k
        LOOP AT resolver-signatures INTO DATA(signature).
          IF k < lines( signature-parameter_categories ) AND signature-parameter_categories[ k + 1 ] = c_category-set.
            requires = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.
      IF requires = abap_false.
        result = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD result_type.
    CASE fun_def-implementation.
      WHEN `SetFunDef`.
        " all members of {<Member1>[, <MemberI>]...} must have the same hierarchy
        IF args IS INITIAL.
          result = zzxxmla1_cl_mdx_type=>set_type( zzxxmla1_cl_mdx_type=>member_type( ) ).
          RETURN.
        ENDIF.
        DATA(first) = to_member_or_tuple_type( args[ 1 ]->get_type( ) ).
        LOOP AT args INTO DATA(arg) FROM 2.
          DATA(type) = to_member_or_tuple_type( arg->get_type( ) ).
          IF first IS NOT BOUND OR type IS NOT BOUND OR first->is_union_compatible( type ) = abap_false.
            fail( |All arguments to function '{ fun_def-name }' must have same hierarchy.| ).
          ENDIF.
        ENDLOOP.
        result = zzxxmla1_cl_mdx_type=>set_type( first ).
      WHEN `ParenthesesFunDef`.
        result = args[ 1 ]->get_type( ).
      WHEN `SetItemFunDef`.
        " the element type of the set
        result = args[ 1 ]->get_type( )->element_type.
      WHEN `TupleFunDef`.
        DATA(members) = VALUE zzxxmla1_cl_mdx_type=>ty_t_type( FOR a IN args ( to_member_type( a->get_type( ) ) ) ).
        check_hierarchies( members ).
        result = zzxxmla1_cl_mdx_type=>tuple_type( members ).
      WHEN `CrossJoinFunDef` OR `NonEmptyCrossJoinFunDef`.
        " CrossJoin(<Set1>, <Set2>) has the type [Hie1] x [Hie2]; * and () take members and tuples too
        DATA(types) = VALUE zzxxmla1_cl_mdx_type=>ty_t_type( ).
        LOOP AT args INTO arg.
          type = arg->get_type( ).
          IF type->is_set( ) = abap_false AND fun_def-name <> `*` AND fun_def-name <> `()`.
            fail( `arg to crossjoin must be a set` ).
          ENDIF.
          add_types( EXPORTING type = type CHANGING types = types ).
        ENDLOOP.
        check_hierarchies( types ).
        result = zzxxmla1_cl_mdx_type=>set_type( zzxxmla1_cl_mdx_type=>tuple_type( types ) ).
      WHEN OTHERS.
        " XtdFunDef, OpeningClosingPeriodFunDef: getResultType without arguments the cube's time hierarchy, a time
        " member for Xtd; compileCall the level and the member of one dimension
        DATA(period_function) = to_upper( fun_def-name ).
        IF period_function = `YTD` OR period_function = `QTD` OR period_function = `MTD` OR period_function = `WTD`
            OR period_function = `OPENINGPERIOD` OR period_function = `CLOSINGPERIOD`.
          DATA(xtd) = xsdbool( period_function <> `OPENINGPERIOD` AND period_function <> `CLOSINGPERIOD` ).
          DATA(time_hierarchy) = COND i( WHEN args IS INITIAL OR ( xtd = abap_false AND lines( args ) = 1 )
                                         THEN schema_reader->get_time_hierarchy( ) ELSE 0 ).
          IF time_hierarchy < 0.
            fail( |Cannot use the function '{ fun_def-name }', no time dimension is available for this cube.| ).
          ENDIF.
          IF args IS INITIAL.
            result = zzxxmla1_cl_mdx_type=>member_type( dimension = schema_reader->dimension_of( time_hierarchy )
                                                        hierarchy = time_hierarchy ).
            IF xtd = abap_true.
              result = zzxxmla1_cl_mdx_type=>set_type( result ).
            ENDIF.
            RETURN.
          ENDIF.
          DATA(first_dimension) = args[ 1 ]->get_type( )->get_dimension( ).
          IF xtd = abap_true.
            IF first_dimension <> zzxxmla1_cl_mdx_type=>c_none
                AND schema_reader->get_dimension( first_dimension )-type <> `TimeDimension`.
              fail( |Argument to function '{ fun_def-name }' must belong to Time hierarchy.| ).
            ENDIF.
          ELSE.
            DATA(member_dimension) = COND i( WHEN lines( args ) = 2 THEN args[ 2 ]->get_type( )->get_dimension( )
                                             ELSE schema_reader->dimension_of( time_hierarchy ) ).
            IF first_dimension <> zzxxmla1_cl_mdx_type=>c_none AND member_dimension <> zzxxmla1_cl_mdx_type=>c_none
                AND first_dimension <> member_dimension.
              fail( |The <level> and <member> arguments to | &&
                    |{ COND #( WHEN period_function = `OPENINGPERIOD` THEN `OpeningPeriod` ELSE `ClosingPeriod` ) } | &&
                    |must be from the same hierarchy. The level was from | &&
                    |'{ schema_reader->get_dimension( first_dimension )-unique_name }' but the member was from | &&
                    |'{ schema_reader->get_dimension( member_dimension )-unique_name }'.| ).
            ENDIF.
          ENDIF.
        ENDIF.
        " ParallelPeriodFunDef, PeriodsToDateFunDef.getResultType: without arguments the cube's time hierarchy
        IF ( to_upper( fun_def-name ) = `PARALLELPERIOD` OR to_upper( fun_def-name ) = `PERIODSTODATE` )
            AND args IS INITIAL.
          DATA(time) = schema_reader->get_time_hierarchy( ).
          IF time < 0.
            fail( |Cannot use the function '{ fun_def-name }', no time dimension is available for this cube.| ).
          ENDIF.
          result = zzxxmla1_cl_mdx_type=>member_type( dimension = schema_reader->dimension_of( time ) hierarchy = time ).
          IF to_upper( fun_def-name ) = `PERIODSTODATE`.
            result = zzxxmla1_cl_mdx_type=>set_type( result ).
          ENDIF.
          RETURN.
        ENDIF.
        IF to_upper( fun_def-name ) = `PARAMETER`
            AND ( fun_def-return_category = c_category-member OR fun_def-return_category = c_category-set ).
          " ParameterFunDef: a member of the type argument's dimension, hierarchy and level; a set of them if the
          " default value is a set
          DATA(type_arg) = args[ 2 ]->get_type( ).
          result = zzxxmla1_cl_mdx_type=>member_type( dimension = type_arg->get_dimension( )
                                                      hierarchy = type_arg->get_hierarchy( )
                                                      level     = type_arg->get_level( ) ).
          IF args[ 3 ]->get_type( )->is_set( ) = abap_true.
            result = zzxxmla1_cl_mdx_type=>set_type( result ).
          ENDIF.
          RETURN.
        ENDIF.
        IF fun_def-resolver_kind = `UdfResolver` AND to_upper( fun_def-name ) = `LASTNONEMPTY`.
          " LastNonEmptyUdf.getReturnType: the element type of the set
          result = args[ 1 ]->get_type( )->element_type.
          RETURN.
        ENDIF.
        IF to_upper( fun_def-name ) = `PERIODSTODATE` AND lines( args ) >= 2.
          DATA(level_hierarchy) = args[ 1 ]->get_type( )->get_hierarchy( ).
          DATA(member_hierarchy) = args[ 2 ]->get_type( )->get_hierarchy( ).
          IF level_hierarchy <> zzxxmla1_cl_mdx_type=>c_none AND member_hierarchy <> zzxxmla1_cl_mdx_type=>c_none
              AND level_hierarchy <> member_hierarchy.
            fail( |Type mismatch: member must belong to hierarchy |
               && |{ schema_reader->get_hierarchy( level_hierarchy )-unique_name }| ).
          ENDIF.
        ENDIF.
        IF to_upper( fun_def-name ) = `GENERATE` AND lines( args ) > 1.
          " GenerateFunDef.getResultType: a string, or a set of the second argument's members or tuples
          DATA(second) = args[ 2 ]->get_type( ).
          IF second->kind = zzxxmla1_cl_mdx_type=>c_kind-string OR second->kind = zzxxmla1_cl_mdx_type=>c_kind-numeric
              OR second->kind = zzxxmla1_cl_mdx_type=>c_kind-decimal.
            result = zzxxmla1_cl_mdx_type=>string( ).
          ELSE.
            result = zzxxmla1_cl_mdx_type=>set_type( to_member_or_tuple_type( second ) ).
          ENDIF.
          RETURN.
        ENDIF.
        result = cast_type( type = COND #( WHEN args IS NOT INITIAL THEN args[ 1 ]->get_type( ) )
                            category = fun_def-return_category ).
        IF result IS NOT BOUND.
          fail( |Cannot deduce type of call to function '{ fun_def-name }'| ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD cast_type.
    CASE category.
      WHEN c_category-logical.
        result = zzxxmla1_cl_mdx_type=>boolean( ).
      WHEN c_category-numeric.
        result = zzxxmla1_cl_mdx_type=>numeric( ).
      WHEN c_category-integer.
        " Category.Numeric | Category.Integer
        result = zzxxmla1_cl_mdx_type=>decimal( 0 ).
      WHEN c_category-string.
        result = zzxxmla1_cl_mdx_type=>string( ).
      WHEN c_category-datetime.
        result = zzxxmla1_cl_mdx_type=>datetime( ).
      WHEN c_category-symbol.
        result = zzxxmla1_cl_mdx_type=>symbol( ).
      WHEN c_category-value.
        result = zzxxmla1_cl_mdx_type=>scalar( ).
      WHEN c_category-dimension.
        IF type IS BOUND.
          result = zzxxmla1_cl_mdx_type=>dimension_for_type(
                     type      = type
                     hierarchy = schema_reader->get_dimension_hierarchy( type->get_dimension( ) ) ).
        ENDIF.
      WHEN c_category-hierarchy.
        IF type IS BOUND.
          result = zzxxmla1_cl_mdx_type=>hierarchy_for_type( type ).
        ENDIF.
      WHEN c_category-level.
        IF type IS BOUND.
          result = zzxxmla1_cl_mdx_type=>level_for_type( type ).
        ENDIF.
      WHEN c_category-member.
        IF type IS BOUND.
          result = to_member_type( type ).
        ENDIF.
        IF result IS NOT BOUND.
          " take a wild guess
          result = zzxxmla1_cl_mdx_type=>member_type( ).
        ENDIF.
      WHEN c_category-tuple.
        IF type IS BOUND.
          result = to_member_or_tuple_type( type ).
        ENDIF.
      WHEN c_category-empty.
        result = zzxxmla1_cl_mdx_type=>empty( ).
      WHEN c_category-set.
        IF type IS BOUND.
          DATA(element) = to_member_or_tuple_type( type ).
          IF element IS BOUND.
            result = zzxxmla1_cl_mdx_type=>set_type( element ).
          ENDIF.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD to_member_type.
    DATA(stripped) = type->strip_set_type( ).
    IF stripped IS BOUND AND stripped->kind = zzxxmla1_cl_mdx_type=>c_kind-tuple AND lines( stripped->element_types ) = 1.
      DATA(hierarchy) = stripped->element_types[ 1 ]->get_hierarchy( ).
      result = zzxxmla1_cl_mdx_type=>member_type(
                 dimension = COND #( WHEN hierarchy <> zzxxmla1_cl_mdx_type=>c_none
                                     THEN schema_reader->dimension_of( hierarchy ) ELSE zzxxmla1_cl_mdx_type=>c_none )
                 hierarchy = hierarchy ).
    ELSE.
      result = type->to_member_type( ).
    ENDIF.
  ENDMETHOD.

  METHOD to_member_or_tuple_type.
    DATA(stripped) = type->strip_set_type( ).
    IF stripped IS BOUND AND stripped->kind = zzxxmla1_cl_mdx_type=>c_kind-tuple.
      result = stripped.
    ELSEIF stripped IS BOUND.
      result = to_member_type( stripped ).
    ENDIF.
  ENDMETHOD.

  METHOD add_types.
    CASE type->kind.
      WHEN zzxxmla1_cl_mdx_type=>c_kind-set.
        add_types( EXPORTING type = type->element_type CHANGING types = types ).
      WHEN zzxxmla1_cl_mdx_type=>c_kind-tuple.
        LOOP AT type->element_types INTO DATA(element).
          add_types( EXPORTING type = element CHANGING types = types ).
        ENDLOOP.
      WHEN zzxxmla1_cl_mdx_type=>c_kind-member.
        APPEND type TO types.
      WHEN OTHERS.
        fail( |Unexpected type: { type->describe( ) }| ).
    ENDCASE.
  ENDMETHOD.

  METHOD check_hierarchies.
    LOOP AT types INTO DATA(type).
      DATA(i) = sy-tabix.
      LOOP AT types INTO DATA(before) TO i - 1.
        IF type->get_hierarchy( ) <> zzxxmla1_cl_mdx_type=>c_none AND type->get_hierarchy( ) = before->get_hierarchy( ).
          fail( |Tuple contains more than one member of hierarchy |
             && |'{ schema_reader->get_hierarchy( type->get_hierarchy( ) )-unique_name }'.| ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD category_of.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
        result = node->fun_def-return_category.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-member.
        result = c_category-member.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-level.
        result = c_category-level.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-hierarchy.
        result = c_category-hierarchy.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-dimension.
        result = c_category-dimension.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-named_set.
        result = c_category-set.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-literal.
        result = SWITCH #( node->category WHEN zzxxmla1_cl_mdx_node=>c_category-numeric THEN c_category-numeric
                                          WHEN zzxxmla1_cl_mdx_node=>c_category-string THEN c_category-string
                                          WHEN zzxxmla1_cl_mdx_node=>c_category-symbol THEN c_category-symbol
                                          ELSE c_category-null ).
      WHEN OTHERS.
        result = node->get_type( )->category( ).
    ENDCASE.
  ENDMETHOD.

  METHOD signature.
    DATA(descriptions) = VALUE string_table( FOR category IN categories
                                             ( |<{ zzxxmla1_cl_mdx_type=>category_description( category ) }>| ) ).
    DATA(first) = VALUE string( descriptions[ 1 ] OPTIONAL ).
    DATA(rest) = descriptions.
    IF rest IS NOT INITIAL.
      DELETE rest INDEX 1.
    ENDIF.
    DATA(returns) = COND string( WHEN return_category <> c_category-unknown
                                 THEN |<{ zzxxmla1_cl_mdx_type=>category_description( return_category ) }> | ).
    CASE syntax.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-property.
        result = |{ first }.{ name }|.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-method.
        result = |{ returns }{ first }.{ name }({ concat_lines_of( table = rest sep = `, ` ) })|.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-infix.
        result = |{ first } { name } { VALUE string( rest[ 1 ] OPTIONAL ) }|.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-prefix.
        result = |{ name } { first }|.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-postfix.
        result = |{ first } { name }|.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-braces.
        result = |\{{ concat_lines_of( table = descriptions sep = `, ` ) }\}|.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-parentheses.
        result = |({ concat_lines_of( table = descriptions sep = `, ` ) })|.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-case.
        IF categories IS NOT INITIAL AND categories[ 1 ] = c_category-logical.
          result = |CASE WHEN { first } THEN <Expression> ... END|.
        ELSE.
          result = |CASE { first } WHEN { first } THEN <Expression> ... END|.
        ENDIF.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-cast.
        result = `CAST(<Expression> AS <Type>)`.
      WHEN zzxxmla1_cl_mdx_node=>c_syntax-empty.
        result = ``.
      WHEN OTHERS.
        result = |{ returns }{ name }({ concat_lines_of( table = descriptions sep = `, ` ) })|.
    ENDCASE.
  ENDMETHOD.

  METHOD fail.
    zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                  description = |olap4abap Error:{ message }| ).
  ENDMETHOD.

  METHOD create_formula_element.
    DATA(parent) = VALUE zzxxmla1_cl_mdx_schema_reader=>ty_element( kind = zzxxmla1_cl_mdx_schema_reader=>c_element-cube ).
    DATA(segments) = formula-name->segments.
    LOOP AT segments INTO DATA(segment).
      IF segment-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
        fail( `Internal error: Calculated member name must not contain member keys` ).
      ENDIF.
      " the last segment is the name of the new member: it is not looked up
      DATA(element) = VALUE zzxxmla1_cl_mdx_schema_reader=>ty_element( ).
      IF sy-tabix < lines( segments ).
        element = schema_reader->get_element_child( parent = parent segment = segment ).
      ENDIF.
      IF element-kind IS INITIAL.
        result = create_calculated_member( parent = parent segment = segment formula = formula ).
        element = VALUE #( kind = zzxxmla1_cl_mdx_schema_reader=>c_element-member id = result-level member = result ).
      ENDIF.
      parent = element.
    ENDLOOP.
  ENDMETHOD.

  METHOD create_calculated_member.
    DATA parent_member TYPE zzxxmla1_cl_mdx_schema_reader=>ty_member.
    DATA hierarchy TYPE i.
    DATA level TYPE i.
    CASE parent-kind.
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-member.
        " a child of the member: on the level below the member's
        parent_member = parent-member.
        hierarchy = parent_member-hier_id.
        DATA(levels) = schema_reader->get_hierarchy( hierarchy )-levels.
        DATA(position) = line_index( levels[ table_line = parent_member-level ] ).
        IF position >= lines( levels ).
          fail( |Internal error: The '{ zzxxmla1_cl_mdx_node=>unparse_segment( segment ) }' calculated member cannot be created |
             && |because its parent is at the lowest level in the |
             && |{ schema_reader->get_hierarchy( hierarchy )-unique_name } hierarchy.| ).
        ENDIF.
        level = levels[ position + 1 ].
        IF parent_member-calculated = abap_true.
          fail( |Internal error: The '{ parent_member-unique_name }' calculated member cannot be used as a parent of another |
             && |calculated member.| ).
        ENDIF.
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-dimension.
        DATA(dimension) = schema_reader->get_dimension( parent-id ).
        hierarchy = dimension-hierarchies[ 1 ].
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-hierarchy.
        hierarchy = parent-id.
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-level.
        hierarchy = schema_reader->get_level( parent-id )-hierarchy.
      WHEN OTHERS.
        fail( |Hierarchy for calculated member '{ formula-name->unparse( ) }' not found| ).
    ENDCASE.
    DATA(hierarchy_info) = schema_reader->get_hierarchy( hierarchy ).
    IF level = 0.
      " below a dimension, hierarchy or level: on the first level of the hierarchy
      level = hierarchy_info-levels[ 1 ].
    ENDIF.
    DATA(level_info) = schema_reader->get_level( level ).

    " RolapMemberBase.setUniqueName: below the parent member, else below the hierarchy ([Measures] for a measure)
    DATA(name) = segment-name.
    DATA(quoted) = zzxxmla1_cl_mdx_node=>quote_identifier( name ).
    DATA(unique_name) = COND string(
      WHEN parent_member-unique_name IS NOT INITIAL THEN |{ parent_member-unique_name }.{ quoted }|
      WHEN hierarchy = zzxxmla1_cl_mdx_schema_reader=>c_measures THEN |[Measures].{ quoted }|
      WHEN name = level_info-name
        THEN |{ hierarchy_info-unique_name }.{ zzxxmla1_cl_mdx_node=>quote_identifier( level_info-name ) }.{ quoted }|
      ELSE |{ hierarchy_info-unique_name }.{ quoted }| ).
    result = VALUE #( hierarchy = hierarchy_info-unique_name hier_id = hierarchy unique_name = unique_name
                      caption = name level = level level_name = level_info-unique_name level_number = level_info-depth
                      parent_unique = parent_member-unique_name calculated = abap_true
                      solve_order = solve_order_of( formula ) ).
  ENDMETHOD.

  METHOD solve_order_of.
    LOOP AT formula-properties INTO DATA(property) WHERE name IS NOT INITIAL.
      IF to_upper( property-name ) <> `SOLVE_ORDER`.
        CONTINUE.
      ENDIF.
      DATA(expression) = property-expression.
      DATA(sign) = 1.
      IF expression->kind = zzxxmla1_cl_mdx_node=>c_kind-call AND expression->name = `-`
          AND expression->syntax = zzxxmla1_cl_mdx_node=>c_syntax-prefix.
        expression = expression->args[ 1 ].
        sign = -1.
      ENDIF.
      IF expression->kind = zzxxmla1_cl_mdx_node=>c_kind-literal
          AND expression->category = zzxxmla1_cl_mdx_node=>c_category-numeric.
        " Number.intValue: the integer part
        result = sign * trunc( expression->number ).
      ENDIF.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD format_expression_of.
    DATA(unique_name) = formula_members[ index ].
    DATA(calculated) = schema_reader->get_calculated_member( unique_name ).
    CASE format_states[ index ].
      WHEN `DONE`.
        result = calculated-format_expression.
        RETURN.
      WHEN `BUSY`.
        " a cyclic reference: no format from here
        RETURN.
    ENDCASE.
    format_states[ index ] = `BUSY`.

    DATA(formula) = formulas[ index ].
    LOOP AT formula-properties INTO DATA(property).
      IF to_upper( property-name ) = `FORMAT_STRING` OR to_upper( property-name ) = `FORMAT`.
        result = property-expression.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF result IS NOT BOUND.
      DATA(type) = formula-expression->get_type( ).
      IF type->kind = zzxxmla1_cl_mdx_type=>c_kind-decimal.
        result = zzxxmla1_cl_mdx_node=>create_string(
                   `#,##0` && COND #( WHEN type->scale > 0 THEN `.` && repeat( val = `0` occ = type->scale ) ) ).
      ELSEIF calculated-member-hier_id = zzxxmla1_cl_mdx_schema_reader=>c_measures.
        result = find_format( formula-expression ).
      ENDIF.
    ENDIF.

    calculated = schema_reader->get_calculated_member( unique_name ).
    calculated-format_expression = result.
    schema_reader->set_calculated_member( calculated ).
    format_states[ index ] = `DONE`.
  ENDMETHOD.

  METHOD find_format.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-member.
        DATA(member) = node->element-member.
        IF member-calculated = abap_true.
          DATA(index) = line_index( formula_members[ table_line = member-unique_name ] ).
          IF index > 0.
            result = format_expression_of( index ).
          ENDIF.
        ELSEIF member-hier_id = zzxxmla1_cl_mdx_schema_reader=>c_measures.
          " a stored measure: its format string (FORMAT_EXP_PARSED), empty if it has none
          result = zzxxmla1_cl_mdx_node=>create_string( schema_reader->measures[ member-measure_index ]-format ).
        ENDIF.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
        LOOP AT node->args INTO DATA(arg).
          result = find_format( arg ).
          IF result IS BOUND.
            RETURN.
          ENDIF.
        ENDLOOP.
    ENDCASE.
  ENDMETHOD.

  METHOD contains_aggregate.
    IF node->kind <> zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      RETURN.
    ENDIF.
    IF to_upper( node->fun_def-name ) = `AGGREGATE`.
      result = abap_true.
      RETURN.
    ENDIF.
    LOOP AT node->args INTO DATA(arg).
      IF contains_aggregate( arg ) = abap_true.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
