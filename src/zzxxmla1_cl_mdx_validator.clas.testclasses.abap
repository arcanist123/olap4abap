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
"! Queries on ZFMSALES as the reference server validates them: the error texts were captured from the container, the resolutions
"! follow the reference's resolvers and conversion costs.
CLASS ltc_validator DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CLASS-DATA reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    CLASS-METHODS class_setup RAISING zzxxmla1_cx_xmla.
    METHODS resolve
      IMPORTING mdx           TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_parser=>ty_query
      RAISING   zzxxmla1_cx_xmla.
    "! The resolved axis of SELECT expr ON 0 FROM [ZFMSALES].
    METHODS axis
      IMPORTING expr          TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node
      RAISING   zzxxmla1_cx_xmla.
    "! The fault's description without the olap4abap Error: prefix.
    METHODS assert_fails
      IMPORTING mdx      TYPE string
                expected TYPE string.
    METHODS assert_axis_fails
      IMPORTING expr     TYPE string
                expected TYPE string.
    METHODS unknown_function FOR TESTING.
    METHODS unknown_objects FOR TESTING.
    METHODS no_matching_signature FOR TESTING.
    METHODS axes_must_be_sets FOR TESTING.
    METHODS hierarchies_in_tuples_and_sets FOR TESTING.
    METHODS axis_numbers FOR TESTING.
    METHODS independent_axes FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS not_implemented FOR TESTING.
    METHODS member_becomes_set FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS cheapest_conversion FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS star_is_crossjoin_of_sets FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS reserved_word_is_symbol FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS empty_argument FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS tuple_of_one_member FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS order_keys FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS named_sets FOR TESTING RAISING zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_validator IMPLEMENTATION.

  METHOD class_setup.
    reader = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
  ENDMETHOD.

  METHOD resolve.
    result = zzxxmla1_cl_mdx_parser=>parse( mdx )-query.
    NEW zzxxmla1_cl_mdx_validator( reader )->resolve_query( CHANGING query = result ).
  ENDMETHOD.

  METHOD axis.
    DATA(query) = resolve( |select { expr } on 0 from [ZFMSALES]| ).
    result = query-axes[ 1 ]-expression.
  ENDMETHOD.

  METHOD assert_fails.
    TRY.
        resolve( mdx ).
        cl_abap_unit_assert=>fail( |{ mdx }: no error| ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        DATA(description) = error->description.
        IF description CP `olap4abap Error:*`.
          description = substring_after( val = description sub = `olap4abap Error:` ).
        ENDIF.
        cl_abap_unit_assert=>assert_equals( act = description exp = expected msg = mdx ).
    ENDTRY.
  ENDMETHOD.

  METHOD assert_axis_fails.
    assert_fails( mdx = |select { expr } on 0 from [ZFMSALES]| expected = expected ).
  ENDMETHOD.

  METHOD unknown_function.
    assert_axis_fails( expr = `Foo([Store])` expected = `No function matches signature 'Foo(<Dimension>)'` ).
  ENDMETHOD.

  METHOD unknown_objects.
    assert_axis_fails( expr = `[Store].[Nowhere]` expected = `MDX object '[Store].[Nowhere]' not found in cube 'ZFMSALES'` ).
    assert_axis_fails( expr = `[Nowhere]` expected = `MDX object '[Nowhere]' not found in cube 'ZFMSALES'` ).
    assert_axis_fails( expr = `[Store].[USA].Foo` expected = `MDX object '[Store].[USA].Foo' not found in cube 'ZFMSALES'` ).
    " FOO is no reserved word of Hierarchize, so it is looked up
    assert_axis_fails( expr = `Hierarchize({[Store].[USA]}, FOO)` expected = `MDX object 'FOO' not found in cube 'ZFMSALES'` ).
  ENDMETHOD.

  METHOD no_matching_signature.
    assert_axis_fails( expr = `[Store].Children.Children` expected = `No function matches signature '<Set>.Children'` ).
    assert_axis_fails( expr     = `[Store].[Store Country].Children`
                       expected = `No function matches signature '<Level>.Children'` ).
    assert_axis_fails( expr     = `CrossJoin([Store], 1)`
                       expected = `No function matches signature 'CrossJoin(<Dimension>, <Numeric Expression>)'` ).
    assert_axis_fails( expr = `Crossjoin({[Store].[USA]})` expected = `No function matches signature 'Crossjoin(<Set>)'` ).
    assert_axis_fails( expr = `{[Measures].[Unit Sales] + 1}` expected = `No function matches signature '{<Numeric Expression>}'` ).
    " inside braces * is the multiplication: the braces take no numbers
    assert_axis_fails( expr = `{[Measures].[Unit Sales] * 2}` expected = `No function matches signature '{<Numeric Expression>}'` ).
  ENDMETHOD.

  METHOD axes_must_be_sets.
    assert_axis_fails( expr = `1` expected = `Axis 'COLUMNS' expression is not a set` ).
    " a level is no set
    assert_axis_fails( expr = `[Customers].[Country]` expected = `Axis 'COLUMNS' expression is not a set` ).
    assert_axis_fails( expr = `[Store].[(All)]` expected = `Axis 'COLUMNS' expression is not a set` ).
  ENDMETHOD.

  METHOD hierarchies_in_tuples_and_sets.
    assert_axis_fails( expr     = `{([Store].[USA], [Store].[Canada])}`
                       expected = `Tuple contains more than one member of hierarchy '[Store]'.` ).
    assert_axis_fails( expr     = `{[Store].[USA], [Product].[All Products]}`
                       expected = `All arguments to function '{}' must have same hierarchy.` ).
  ENDMETHOD.

  METHOD axis_numbers.
    assert_fails( mdx = `select {} on 0, {} on 0 from [ZFMSALES]` expected = `Duplicate axis name 'COLUMNS'.` ).
    assert_fails( mdx      = `select {} on 1 from [ZFMSALES]`
                  expected = `Axis numbers specified in a query must be sequentially specified, and cannot contain gaps. `
                          && `Axis 0 (COLUMNS) is missing.` ).
  ENDMETHOD.

  METHOD independent_axes.
    assert_fails( mdx      = `select {[Store].[USA]} on 0 from [ZFMSALES] where [Store].[Canada]`
                  expected = `Hierarchy '[Store]' appears in more than one independent axis.` ).
    " the dimension [Store] stands for its hierarchy named like it (DimensionType.getHierarchy), so both axes use it
    assert_fails( mdx      = `select [Store].Members on 0, [Store].Children on 1 from [ZFMSALES]`
                  expected = `Hierarchy '[Store]' appears in more than one independent axis.` ).
    resolve( `select [Store.Store Type].Members on 0, [Store].Children on 1 from [ZFMSALES]` ).
  ENDMETHOD.

  METHOD not_implemented.
    assert_axis_fails( expr     = `StrToSet("{[Product].[Food]}")`
                       expected = `The function StrToSet(<String Expression>) is not implemented yet` ).
  ENDMETHOD.

  METHOD named_sets.
    " a named set is a NamedSetExpr of its expression's set type; sets may refer to sets defined after them
    DATA(query) = resolve( `with set [B] as '{[A], [Product].[Food]}' set [A] as '{[Product].[Drink]}' `
                        && `select [B] on 0 from [ZFMSALES]` ).
    DATA(set) = query-axes[ 1 ]-expression.
    cl_abap_unit_assert=>assert_equals( act = set->kind exp = zzxxmla1_cl_mdx_node=>c_kind-named_set ).
    cl_abap_unit_assert=>assert_equals( act = set->unparse( ) exp = `[B]` ).
    cl_abap_unit_assert=>assert_equals( act = set->get_type( )->is_set( ) exp = abap_true ).
    " errors of the reference server: the name as written, a set expression, one segment, no self-reference
    assert_fails( mdx = `with set [B] as '{[Product].[Drink]}' select [b] on 0 from [ZFMSALES]`
                  expected = `MDX object '[b]' not found in cube 'ZFMSALES'` ).
    assert_fails( mdx = `with set [S] as '[Product].[Drink]' select [S] on 0 from [ZFMSALES]`
                  expected = `Set expression '[S]' must be a set` ).
    assert_fails( mdx = `with set [A].[B] as '{[Product].[Drink]}' select [A].[B] on 0 from [ZFMSALES]`
                  expected = `Internal error: assert failed: set names must not be compound` ).
    assert_fails( mdx = `with set [S] as '{[S]}' select [S] on 0 from [ZFMSALES]`
                  expected = `No function matches signature '{<Set>}'` ).
    assert_fails( mdx = `with member [Measures].[x] as '[Product].CurrentOrdinal' select [Measures].[x] on 0 `
                     && `from [ZFMSALES]`
                  expected = `No function matches signature '<Dimension>.CurrentOrdinal'` ).
    " an alias is a dynamic named set in the call around its AS
    set = axis( `{[Product].[Product Family].Members as t, t.Item(1)}` ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 1 ]->fun_def-implementation exp = `AsFunDef` ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 1 ]->args[ 2 ]->set_dynamic exp = abap_true ).
  ENDMETHOD.

  METHOD member_becomes_set.
    " QueryAxis.resolve: a member on an axis is put in braces
    DATA(set) = axis( `[Measures].[Unit Sales]` ).
    cl_abap_unit_assert=>assert_equals( act = set->fun_def-implementation exp = `SetFunDef` ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 1 ]->kind exp = zzxxmla1_cl_mdx_node=>c_kind-member ).
    cl_abap_unit_assert=>assert_equals( act = set->get_type( )->describe( )
                                        exp = `SetType<MemberType<member=[Measures].[Unit Sales]>>` ).
    DATA(query) = resolve( `select from [ZFMSALES] where [Measures].[Store Cost]` ).
    cl_abap_unit_assert=>assert_equals( act = query-slicer->unparse( ) exp = `{[Measures].[Store Cost]}` ).
  ENDMETHOD.

  METHOD cheapest_conversion.
    " [Store] is a dimension: to a hierarchy costs 2, to a level 3, so <Hierarchy>.Members wins over <Level>.Members
    DATA(members) = axis( `[Store].Members` ).
    cl_abap_unit_assert=>assert_equals( act = members->fun_def-signature exp = `<Hierarchy>.Members` ).
    cl_abap_unit_assert=>assert_equals( act = members->args[ 1 ]->kind exp = zzxxmla1_cl_mdx_node=>c_kind-dimension ).
    " the result type comes from the argument as it is: the member type of the dimension, whose hierarchy is the one
    " named like the dimension
    DATA(hierarchies) = reader->get_hierarchies( ).
    cl_abap_unit_assert=>assert_equals( act = members->get_type( )->get_hierarchy( )
                                        exp = hierarchies[ unique_name = `[Store]` ]-id ).
    DATA(children) = axis( `[Store].CurrentMember.Children` ).
    cl_abap_unit_assert=>assert_equals( act = children->fun_def-signature exp = `<Member>.Children` ).
    cl_abap_unit_assert=>assert_equals( act = children->args[ 1 ]->fun_def-signature exp = `<Hierarchy>.CurrentMember` ).
  ENDMETHOD.

  METHOD star_is_crossjoin_of_sets.
    DATA(set) = axis( `[Store].[USA] * [Product].Children` ).
    cl_abap_unit_assert=>assert_equals( act = set->fun_def-implementation exp = `CrossJoinFunDef` ).
    " a MultiResolver takes its first signature that matches: <Set> * <Set>, the member converts to a set
    cl_abap_unit_assert=>assert_equals( act = set->fun_def-signature_categories exp = VALUE zzxxmla1_cl_mdx_funtable=>ty_t_category( ( 8 ) ( 8 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 1 ]->fun_def-implementation exp = `SetFunDef` ).
    cl_abap_unit_assert=>assert_equals( act = set->get_type( )->get_arity( ) exp = 2 ).
    " CrossJoin takes sets: the member is put in braces
    set = axis( `CrossJoin([Store].[USA], [Product].Children)` ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 1 ]->fun_def-implementation exp = `SetFunDef` ).
  ENDMETHOD.

  METHOD reserved_word_is_symbol.
    DATA(set) = axis( `Hierarchize([Store].Members, POST)` ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 2 ]->category exp = zzxxmla1_cl_mdx_node=>c_category-symbol ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 2 ]->value exp = `POST` ).
  ENDMETHOD.

  METHOD empty_argument.
    DATA(set) = axis( `DrilldownLevelTop({[Product].[All Products]},3,,[Measures].[Unit Sales])` ).
    cl_abap_unit_assert=>assert_equals( act = set->fun_def-signature_categories exp = VALUE zzxxmla1_cl_mdx_funtable=>ty_t_category( ( 8 ) ( 7 ) ( 17 ) ( 7 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 3 ]->syntax exp = zzxxmla1_cl_mdx_node=>c_syntax-empty ).
  ENDMETHOD.

  METHOD tuple_of_one_member.
    " ([Store].[USA]) is a tuple, which the axis puts in braces
    DATA(set) = axis( `([Store].[USA])` ).
    cl_abap_unit_assert=>assert_equals( act = set->fun_def-implementation exp = `SetFunDef` ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 1 ]->fun_def-implementation exp = `TupleFunDef` ).
    cl_abap_unit_assert=>assert_equals( act = set->get_type( )->get_arity( ) exp = 1 ).
  ENDMETHOD.

  METHOD order_keys.
    " OrderFunDef.ResolverImpl: the set, then each key a value with an optional symbol (8 set, 13 value, 11 symbol)
    DATA(set) = axis( `Order([Product].Children, [Measures].[Unit Sales], BASC)` ).
    cl_abap_unit_assert=>assert_equals( act = set->fun_def-implementation exp = `OrderFunDef` ).
    cl_abap_unit_assert=>assert_equals( act = set->fun_def-parameter_categories
                                        exp = VALUE zzxxmla1_cl_mdx_funtable=>ty_t_category( ( 8 ) ( 13 ) ( 11 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 3 ]->value exp = `BASC` ).
    set = axis( `Order({[Product].[Food]}, [Measures].[Unit Sales], [Product].CurrentMember.Name, DESC)` ).
    cl_abap_unit_assert=>assert_equals( act = set->fun_def-parameter_categories
                                        exp = VALUE zzxxmla1_cl_mdx_funtable=>ty_t_category( ( 8 ) ( 13 ) ( 13 ) ( 11 ) ) ).
    " a member becomes a set; the type is the set's
    set = axis( `Order([Product].[Food], [Measures].[Unit Sales])` ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 1 ]->fun_def-implementation exp = `SetFunDef` ).
    cl_abap_unit_assert=>assert_equals( act = set->get_type( )->is_set( ) exp = abap_true ).
    " texts from the reference server
    assert_axis_fails( expr = `Order({[Product].[Food]})` expected = `No function matches signature 'Order(<Set>)'` ).
  ENDMETHOD.

ENDCLASS.

"! Calculated members (WITH MEMBER): every test resolves with a schema reader of its own, which then holds the members.
CLASS ltc_formulas DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    METHODS setup RAISING zzxxmla1_cx_xmla.
    METHODS resolve
      IMPORTING mdx           TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_parser=>ty_query
      RAISING   zzxxmla1_cx_xmla.
    "! The format expression of the calculated member as text: the string of a literal, NONE if there is none.
    METHODS format_of
      IMPORTING unique_name   TYPE string
      RETURNING VALUE(result) TYPE string.
    METHODS assert_fails
      IMPORTING mdx      TYPE string
                expected TYPE string.
    METHODS member_of_measures FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS member_of_other_hierarchy FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS formulas_refer_to_each_other FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS solve_order FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS formats FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS errors FOR TESTING.
    METHODS cast_types FOR TESTING RAISING zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_formulas IMPLEMENTATION.

  METHOD setup.
    reader = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
  ENDMETHOD.

  METHOD resolve.
    result = zzxxmla1_cl_mdx_parser=>parse( mdx )-query.
    NEW zzxxmla1_cl_mdx_validator( reader )->resolve_query( CHANGING query = result ).
  ENDMETHOD.

  METHOD format_of.
    DATA(expression) = reader->get_calculated_member( unique_name )-format_expression.
    result = COND #( WHEN expression IS NOT BOUND THEN `NONE`
                     WHEN expression->kind = zzxxmla1_cl_mdx_node=>c_kind-literal THEN expression->value
                     ELSE expression->unparse( ) ).
  ENDMETHOD.

  METHOD assert_fails.
    TRY.
        resolve( mdx ).
        cl_abap_unit_assert=>fail( |{ mdx }: no error| ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->description exp = |olap4abap Error:{ expected }| msg = mdx ).
    ENDTRY.
  ENDMETHOD.

  METHOD member_of_measures.
    " the name keeps the case of the formula's name; the identifier on the axis finds the member case-insensitively
    DATA(query) = resolve( `with member measures.x as '1 + 2' select {[Measures].[X]} on 0 from [ZFMSALES]` ).
    DATA(member) = query-axes[ 1 ]-expression->args[ 1 ]->element-member.
    cl_abap_unit_assert=>assert_equals( act = member-unique_name exp = `[Measures].[x]` ).
    cl_abap_unit_assert=>assert_true( member-calculated ).
    cl_abap_unit_assert=>assert_equals( act = member-level_name exp = `[Measures].[MeasuresLevel]` ).
    cl_abap_unit_assert=>assert_equals( act = member-level_number exp = 0 ).
    DATA(calculated) = reader->get_calculated_member( `[Measures].[x]` ).
    cl_abap_unit_assert=>assert_equals( act = calculated-expression->fun_def-name exp = `+` ).
    cl_abap_unit_assert=>assert_false( calculated-contains_aggregate ).
  ENDMETHOD.

  METHOD member_of_other_hierarchy.
    " a member below a hierarchy is on its first level, the All level
    resolve( `WITH MEMBER [Product].[Calculated Member] as 'AGGREGATE({})' `
          && `SELECT {[Measures].[Unit Sales]} on 0 from [ZFMSALES] WHERE ([Product].[Calculated Member])` ).
    DATA(calculated) = reader->get_calculated_member( `[Product].[Calculated Member]` ).
    cl_abap_unit_assert=>assert_equals( act = calculated-member-level_name exp = `[Product].[(All)]` ).
    cl_abap_unit_assert=>assert_true( calculated-contains_aggregate ).
    " a member below the All member keeps it in its unique name
    resolve( `with member [Store].[All Stores].[Two] as 2 select {[Store].[All Stores].[Two]} on 0 from [ZFMSALES]` ).
    calculated = reader->get_calculated_member( `[Store].[All Stores].[Two]` ).
    cl_abap_unit_assert=>assert_equals( act = calculated-member-parent_unique exp = `[Store].[All Stores]` ).
    cl_abap_unit_assert=>assert_equals( act = calculated-member-level_number exp = 1 ).
  ENDMETHOD.

  METHOD formulas_refer_to_each_other.
    " a formula may use a member defined after it
    resolve( `with member [Measures].[Foo] as [Measures].[Bar] / 2 member [Measures].[Bar] as 4 `
          && `select [Measures].[Foo] on 0 from [ZFMSALES]` ).
    DATA(foo) = reader->get_calculated_member( `[Measures].[Foo]` ).
    cl_abap_unit_assert=>assert_equals( act = foo-expression->args[ 1 ]->element-member-unique_name
                                        exp = `[Measures].[Bar]` ).
  ENDMETHOD.

  METHOD solve_order.
    resolve( `with member [Measures].[A] as 1, SOLVE_ORDER = 5 member [Measures].[B] as 2, solve_order = -3 `
          && `member [Measures].[C] as 3 select from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_calculated_member( `[Measures].[A]` )-member-solve_order
                                        exp = 5 ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_calculated_member( `[Measures].[B]` )-member-solve_order
                                        exp = -3 ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_calculated_member( `[Measures].[C]` )-member-solve_order
                                        exp = 0 ).
  ENDMETHOD.

  METHOD formats.
    resolve( `with member [Measures].[Explicit] as 1, FORMAT_STRING = '#,##0.00' `
          && `member [Measures].[Ratio] as ([Measures].[Store Sales] - [Measures].[Store Cost]) / [Measures].[Store Cost] `
          && `member [Measures].[Third] as 1 / 3 `
          && `member [Measures].[Derived] as [Measures].[Explicit] * 2 `
          && `member [Product].[Other] as 1 `
          && `select from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = format_of( `[Measures].[Explicit]` ) exp = `#,##0.00` ).
    " the first member that has a format: the stored measure Store Sales, which has no format string
    cl_abap_unit_assert=>assert_equals( act = format_of( `[Measures].[Ratio]` ) exp = `` ).
    cl_abap_unit_assert=>assert_equals( act = format_of( `[Measures].[Third]` ) exp = `NONE` ).
    cl_abap_unit_assert=>assert_equals( act = format_of( `[Measures].[Derived]` ) exp = `#,##0.00` ).
    " no inference for members of other hierarchies
    cl_abap_unit_assert=>assert_equals( act = format_of( `[Product].[Other]` ) exp = `NONE` ).
  ENDMETHOD.

  METHOD errors.
    " texts from the reference server
    assert_fails( mdx      = `with member Foo as 1 select from [ZFMSALES]`
                  expected = `Hierarchy for calculated member 'Foo' not found` ).
    assert_fails( mdx      = `with member [Store].&[1].[X] as 1 select from [ZFMSALES]`
                  expected = `Internal error: Calculated member name must not contain member keys` ).
    assert_fails( mdx      = `with member [Store].[USA].[WA].[Bremerton].[Store 3].[X] as 1 select from [ZFMSALES]`
                  expected = `Internal error: The '[X]' calculated member cannot be created because its parent is at `
                          && `the lowest level in the [Store] hierarchy.` ).
    assert_fails( mdx      = `with member [Store.Store Id].[1].[X] as 1 select from [ZFMSALES]`
                  expected = `Internal error: The '[X]' calculated member cannot be created because its parent is at `
                          && `the lowest level in the [Store.Store Id] hierarchy.` ).
    assert_fails( mdx      = `with member [Measures].[A] as 1 member [Measures].[A].[B] as 2 select from [ZFMSALES]`
                  expected = `Internal error: The '[B]' calculated member cannot be created because its parent is at `
                          && `the lowest level in the [Measures] hierarchy.` ).
    assert_fails( mdx      = `with member [Measures].[A] as {[Store].Children} select from [ZFMSALES]`
                  expected = `Member expression '{[Store].Children}' must not be a set` ).
  ENDMETHOD.

  METHOD cast_types.
    " CastFunDef.ResolverImpl: the type name, in any case, gives the result category
    DATA(query) = resolve( `with member measures.a as cast(123 as string) member measures.b as cast('1' as Numeric) `
                        && `member measures.c as cast(1 as BOOLEAN) member measures.d as cast(2.5 as integer) `
                        && `select from [ZFMSALES]` ).
    DATA(categories) = VALUE zzxxmla1_cl_mdx_funtable=>ty_t_category(
                         FOR formula IN query-formulas ( formula-expression->fun_def-return_category ) ).
    cl_abap_unit_assert=>assert_equals( act = categories
                                        exp = VALUE zzxxmla1_cl_mdx_funtable=>ty_t_category( ( 9 ) ( 7 ) ( 5 ) ( 15 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = query-formulas[ 1 ]-expression->fun_def-implementation exp = `CastFunDef` ).
    cl_abap_unit_assert=>assert_equals( act = query-formulas[ 1 ]-expression->get_type( )->kind
                                        exp = zzxxmla1_cl_mdx_type=>c_kind-string ).
    " text from the reference server; the name as written
    assert_fails( mdx      = `with member measures.x as cast(1 as foo) select from [ZFMSALES]`
                  expected = `Unknown type 'foo'; values are NUMERIC, STRING, BOOLEAN` ).
  ENDMETHOD.

ENDCLASS.
