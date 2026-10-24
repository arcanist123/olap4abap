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
"! The cases of ParserTest (olap/ParserTest.java) for the JavaCC parser, with the expected texts of
"! its TestParser unparse, and the error texts the reference server answers (where ParserTest checks the old JavaCUP parser, the
"! positions and tokens are the ones the reference server gives). In the texts, \n stands for a newline.
CLASS ltc_parser_test DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! \n in the text as newline.
    METHODS text
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE string.
    METHODS assert_query
      IMPORTING mdx      TYPE string
                expected TYPE string.
    "! The expression as the formula of WITH MEMBER [Measures].[Foo] AS expr SELECT FROM [Sales] (ParserTest.wrapExpr).
    METHODS assert_expr
      IMPORTING expr     TYPE string
                expected TYPE string.
    "! The description of the fault, without the olap4abap Error: prefix of syntax errors.
    METHODS assert_fails
      IMPORTING mdx      TYPE string
                expected TYPE string.
    METHODS wrap
      IMPORTING expr          TYPE string
      RETURNING VALUE(result) TYPE string.

    METHODS axis_parsing FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS negative_cases FOR TESTING.
    METHODS scanner_punc FOR TESTING.
    METHODS multiple_axes FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS member_on_axis FOR TESTING.
    METHODS case_test FOR TESTING.
    METHODS case_switch FOR TESTING.
    METHODS set_expr FOR TESTING.
    METHODS dimension_properties FOR TESTING.
    METHODS cell_properties FOR TESTING.
    METHODS is_empty FOR TESTING.
    METHODS is FOR TESTING.
    METHODS is_null FOR TESTING.
    METHODS null FOR TESTING.
    METHODS cast FOR TESTING.
    METHODS bang_function FOR TESTING.
    METHODS id FOR TESTING.
    METHODS id_with_key FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS id_complex FOR TESTING.
    METHODS numbers FOR TESTING.
    METHODS large_precision FOR TESTING.
    METHODS empty_expr FOR TESTING.
    METHODS as_precedence FOR TESTING.
    METHODS drill_through FOR TESTING.
    METHODS explain FOR TESTING.
    METHODS multiple_spaces FOR TESTING.
    METHODS children FOR TESTING RAISING zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_parser_test IMPLEMENTATION.

  METHOD text.
    result = replace( val = value sub = `\n` with = cl_abap_char_utilities=>newline occ = 0 ).
  ENDMETHOD.

  METHOD wrap.
    result = |with member [Measures].[Foo] as { expr }{ cl_abap_char_utilities=>newline } select from [Sales]|.
  ENDMETHOD.

  METHOD assert_query.
    TRY.
        DATA(statement) = zzxxmla1_cl_mdx_parser=>parse( text( mdx ) ).
        cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_parser=>to_mdx( statement ) exp = text( expected ) ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>fail( |{ mdx }: { error->description }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD assert_expr.
    TRY.
        DATA(statement) = zzxxmla1_cl_mdx_parser=>parse( wrap( text( expr ) ) ).
        cl_abap_unit_assert=>assert_equals( act = statement-query-formulas[ 1 ]-expression->unparse( ) exp = expected ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>fail( |{ expr }: { error->description }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD assert_fails.
    TRY.
        zzxxmla1_cl_mdx_parser=>parse( text( mdx ) ).
        cl_abap_unit_assert=>fail( |{ mdx }: no error| ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        DATA(description) = error->description.
        IF description CP `olap4abap Error:*`.
          description = substring_after( val = description sub = `olap4abap Error:` ).
        ENDIF.
        cl_abap_unit_assert=>assert_equals( act = description exp = expected msg = mdx ).
    ENDTRY.
  ENDMETHOD.

  METHOD axis_parsing.
    DATA(names) = VALUE string_table( ( `COLUMNS` ) ( `ROWS` ) ( `PAGES` ) ( `CHAPTERS` ) ( `SECTIONS` ) ).
    LOOP AT names INTO DATA(name).
      DATA(ordinal) = sy-tabix - 1.
      DATA(ways) = VALUE string_table( ( |{ ordinal }| ) ( |AXIS({ ordinal })| ) ( name ) ).
      LOOP AT ways INTO DATA(way).
        DATA(statement) = zzxxmla1_cl_mdx_parser=>parse( |select [member] on { way } from [cube]| ).
        cl_abap_unit_assert=>assert_equals( act = lines( statement-query-axes ) exp = 1 ).
        cl_abap_unit_assert=>assert_equals( act = statement-query-axes[ 1 ]-ordinal exp = ordinal msg = way ).
        cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_mdx_parser=>axis_name( statement-query-axes[ 1 ]-ordinal )
                                            exp = name ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD negative_cases.
    assert_fails( mdx      = `select [member] on axis(1.7) from sales`
                  expected = `Invalid axis specification. The axis number must be a non-negative integer, but it was 1.7.` ).
    assert_fails( mdx = `select [member] on axis(-1) from sales` expected = `Syntax error at line 1, column 25, token '-'` ).
    assert_query( mdx = `select [member] on axis(5) from sales` expected = `select [member] ON AXIS(5)\nfrom [sales]\n` ).
    assert_fails( mdx = `select [member] on axes(0) from sales` expected = `Syntax error at line 1, column 20, token 'axes'` ).
    assert_fails( mdx      = `select [member] on 0.5 from sales`
                  expected = `Invalid axis specification. The axis number must be a non-negative integer, but it was 0.5.` ).
    assert_query( mdx = `select [member] on 555 from sales` expected = `select [member] ON AXIS(555)\nfrom [sales]\n` ).
  ENDMETHOD.

  METHOD scanner_punc.
    assert_query( mdx      = `with member [Measures].__Foo as 1 + 2\nselect __Foo on 0\nfrom _Bar_Baz`
                  expected = `with member [Measures].__Foo as '(1 + 2)'\nselect __Foo ON COLUMNS\nfrom [_Bar_Baz]\n` ).
    assert_fails( mdx      = `with member [Measures].#_Foo as 1 + 2\nselect __Foo on 0\nfrom _Bar#Baz`
                  expected = `Lexical error at line 1, column 24.  Encountered: "#" (35), after : ""` ).
    assert_query( mdx      = `with member [Measures].$Foo as 1 + 2\nselect $Foo on 0\nfrom Bar$Baz`
                  expected = `with member [Measures].$Foo as '(1 + 2)'\nselect $Foo ON COLUMNS\nfrom [Bar$Baz]\n` ).
    assert_query( mdx      = `select [measures].[$foo] on columns from sales`
                  expected = `select [measures].[$foo] ON COLUMNS\nfrom [sales]\n` ).
    assert_fails( mdx      = `select { Customers].Children } on columns from [Sales]`
                  expected = `Lexical error at line 1, column 19.  Encountered: "]" (93), after : ""` ).
  ENDMETHOD.

  METHOD multiple_axes.
    DATA(statement) = zzxxmla1_cl_mdx_parser=>parse( `select {[axis0mbr]} on axis(0), {[axis1mbr]} on axis(1) from [cube]` ).
    cl_abap_unit_assert=>assert_equals( act = lines( statement-query-axes ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = statement-query-axes[ 2 ]-ordinal exp = 1 ).
    DATA(set) = statement-query-axes[ 1 ]-expression.
    cl_abap_unit_assert=>assert_equals( act = set->syntax exp = zzxxmla1_cl_mdx_node=>c_syntax-braces ).
    cl_abap_unit_assert=>assert_equals( act = set->args[ 1 ]->segments[ 1 ]-name exp = `axis0mbr` ).
    statement = zzxxmla1_cl_mdx_parser=>parse( `select {[axis1mbr]} on aXiS(1), {[axis0mbr]} on AxIs(0) from [cube]` ).
    cl_abap_unit_assert=>assert_equals( act = statement-query-axes[ 1 ]-ordinal exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = statement-query-axes[ 2 ]-ordinal exp = 0 ).
  ENDMETHOD.

  METHOD member_on_axis.
    assert_query(
      mdx      = `select [Measures].[Sales Count] on 0, non empty [Store].[Store State].members on 1 from [Sales]`
      expected = `select [Measures].[Sales Count] ON COLUMNS,\n  NON EMPTY [Store].[Store State].members ON ROWS\nfrom [Sales]\n` ).
  ENDMETHOD.

  METHOD case_test.
    assert_query(
      mdx      = `with member [Measures].[Foo] as  ' case when x = y then "eq" when x < y then "lt" else "gt" end '`
              && `select {[foo]} on axis(0) from [cube]`
      expected = `with member [Measures].[Foo] as 'CASE WHEN (x = y) THEN "eq" WHEN (x < y) THEN "lt" ELSE "gt" END'\n`
              && `select {[foo]} ON COLUMNS\nfrom [cube]\n` ).
  ENDMETHOD.

  METHOD case_switch.
    assert_query(
      mdx      = `with member [Measures].[Foo] as  ' case x when 1 then 2 when 3 then 4 else 5 end '`
              && `select {[foo]} on axis(0) from [cube]`
      expected = `with member [Measures].[Foo] as 'CASE x WHEN 1 THEN 2 WHEN 3 THEN 4 ELSE 5 END'\nselect {[foo]} ON COLUMNS\n`
              && `from [cube]\n` ).
  ENDMETHOD.

  METHOD set_expr.
    assert_query(
      mdx      = `with set [Set1] as '[Product].[Drink]:[Product].[Food]' \n`
              && `select [Set1] on columns, {[Measures].defaultMember} on rows \nfrom Sales`
      expected = `with set [Set1] as '([Product].[Drink] : [Product].[Food])'\n`
              && `select [Set1] ON COLUMNS,\n  {[Measures].defaultMember} ON ROWS\nfrom [Sales]\n` ).
    assert_query(
      mdx      = `select [Product].[Drink]:[Product].[Food] on columns,\n {[Measures].defaultMember} on rows \nfrom Sales`
      expected = `select ([Product].[Drink] : [Product].[Food]) ON COLUMNS,\n  {[Measures].defaultMember} ON ROWS\n`
              && `from [Sales]\n` ).
  ENDMETHOD.

  METHOD dimension_properties.
    assert_query( mdx      = `select {[foo]} properties p1,   p2 on columns from [cube]`
                  expected = `select {[foo]} DIMENSION PROPERTIES p1, p2 ON COLUMNS\nfrom [cube]\n` ).
  ENDMETHOD.

  METHOD cell_properties.
    assert_query( mdx      = `select {[foo]} on columns from [cube] CELL PROPERTIES FORMATTED_VALUE`
                  expected = `select {[foo]} ON COLUMNS\nfrom [cube]\n[FORMATTED_VALUE]` ).
  ENDMETHOD.

  METHOD is_empty.
    assert_expr( expr = `[Measures].[Unit Sales] IS EMPTY` expected = `([Measures].[Unit Sales] IS EMPTY)` ).
    assert_expr( expr     = `[Measures].[Unit Sales] IS EMPTY AND 1 IS NULL`
                 expected = `(([Measures].[Unit Sales] IS EMPTY) AND (1 IS NULL))` ).
  ENDMETHOD.

  METHOD is.
    assert_expr( expr     = `[Measures].[Unit Sales] IS [Measures].[Unit Sales] AND [Measures].[Unit Sales] IS NULL`
                 expected = `(([Measures].[Unit Sales] IS [Measures].[Unit Sales]) AND ([Measures].[Unit Sales] IS NULL))` ).
  ENDMETHOD.

  METHOD is_null.
    assert_expr( expr = `[Measures].[Unit Sales] IS NULL` expected = `([Measures].[Unit Sales] IS NULL)` ).
    assert_expr( expr     = `[Measures].[Unit Sales] IS NULL AND 1 <> 2`
                 expected = `(([Measures].[Unit Sales] IS NULL) AND (1 <> 2))` ).
    assert_expr( expr = `x is null or y is null and z = 5` expected = `((x IS NULL) OR ((y IS NULL) AND (z = 5)))` ).
    assert_expr( expr = `(x is null) + 56 > 6` expected = `((((x IS NULL)) + 56) > 6)` ).
  ENDMETHOD.

  METHOD null.
    assert_expr( expr     = `Filter({[Measures].[Foo]}, Iif(1 = 2, NULL, 'X'))`
                 expected = `Filter({[Measures].[Foo]}, Iif((1 = 2), NULL, "X"))` ).
  ENDMETHOD.

  METHOD cast.
    assert_expr( expr = `Cast([Measures].[Unit Sales] AS Numeric)` expected = `CAST([Measures].[Unit Sales] AS Numeric)` ).
    assert_expr( expr = `Cast(1 + 2 AS String)` expected = `CAST((1 + 2) AS String)` ).
  ENDMETHOD.

  METHOD bang_function.
    " the qualifiers before ! are ignored
    assert_expr( expr = `foo!bar!Exp(2.0)` expected = `Exp(2.0)` ).
    assert_expr( expr = `1 + VBA!Exp(2.0 + 3)` expected = `(1 + Exp((2.0 + 3)))` ).
  ENDMETHOD.

  METHOD id.
    assert_expr( expr = `foo` expected = `foo` ).
    assert_expr( expr = `fOo` expected = `fOo` ).
    assert_expr( expr = `[Foo].[Bar Baz]` expected = `[Foo].[Bar Baz]` ).
    assert_expr( expr = `[Foo].&[Bar]` expected = `[Foo].&[Bar]` ).
  ENDMETHOD.

  METHOD id_with_key.
    " two segments each with a compound key
    DATA(mdx) = `[Foo].&Key1&Key2.&[Key3]&Key4&[5]`.
    assert_expr( expr = mdx expected = mdx ).
    DATA(statement) = zzxxmla1_cl_mdx_parser=>parse( wrap( mdx ) ).
    DATA(id) = statement-query-formulas[ 1 ]-expression.
    cl_abap_unit_assert=>assert_equals( act = id->kind exp = zzxxmla1_cl_mdx_node=>c_kind-id ).
    cl_abap_unit_assert=>assert_equals( act = lines( id->segments ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = id->segments[ 1 ] exp = VALUE zzxxmla1_cl_mdx_node=>ty_segment(
                                          name = `Foo` quoting = zzxxmla1_cl_mdx_node=>c_quoting-quoted ) ).
    cl_abap_unit_assert=>assert_equals( act = id->segments[ 2 ]-quoting exp = zzxxmla1_cl_mdx_node=>c_quoting-key ).
    cl_abap_unit_assert=>assert_equals( act = id->segments[ 2 ]-keys exp = VALUE zzxxmla1_cl_mdx_node=>ty_t_name_segment(
                                          ( name = `Key1` quoting = zzxxmla1_cl_mdx_node=>c_quoting-unquoted )
                                          ( name = `Key2` quoting = zzxxmla1_cl_mdx_node=>c_quoting-unquoted ) ) ).
    cl_abap_unit_assert=>assert_equals( act = id->segments[ 3 ]-keys exp = VALUE zzxxmla1_cl_mdx_node=>ty_t_name_segment(
                                          ( name = `Key3` quoting = zzxxmla1_cl_mdx_node=>c_quoting-quoted )
                                          ( name = `Key4` quoting = zzxxmla1_cl_mdx_node=>c_quoting-unquoted )
                                          ( name = `5` quoting = zzxxmla1_cl_mdx_node=>c_quoting-quoted ) ) ).
  ENDMETHOD.

  METHOD id_complex.
    assert_expr( expr = `[Foo].&[Key1]&[Key2].[Bar]` expected = `[Foo].&[Key1]&[Key2].[Bar]` ).
    assert_expr( expr = `[Foo].&[1]&[Key 2]&[3].[Bar]` expected = `[Foo].&[1]&[Key 2]&[3].[Bar]` ).
    assert_expr( expr = `[Foo].&Key1&Key2 + 4` expected = `([Foo].&Key1&Key2 + 4)` ).
    assert_expr( expr = `[Foo].&[_Key2].[Bar]` expected = `[Foo].&[_Key2].[Bar]` ).
  ENDMETHOD.

  METHOD numbers.
    assert_expr( expr = `2` expected = `2` ).
    " a leading - is an operator, a leading + is ignored
    assert_expr( expr = `-3` expected = `(- 3)` ).
    assert_expr( expr = `+45` expected = `45` ).
    assert_fails( mdx = wrap( `4 5` ) expected = `Syntax error at line 1, column 35, token '5'` ).
    assert_expr( expr = `3.14` expected = `3.14` ).
    assert_expr( expr = `.12345` expected = `0.12345` ).
    assert_expr( expr = `31415926535.89793` expected = `31415926535.89793` ).
    assert_expr( expr = `31415926535897.9314159265358979` expected = `31415926535897.9314159265358979` ).
    assert_expr( expr = `3.141592653589793` expected = `3.141592653589793` ).
    assert_expr( expr = `-3141592653589793.14159265358979` expected = `(- 3141592653589793.14159265358979)` ).
    assert_expr( expr = `1e2` expected = `1E+2` ).
    assert_fails( mdx = wrap( `1e2e3` ) expected = `Syntax error at line 1, column 36, token 'e3'` ).
    assert_expr( expr = `1.2e3` expected = `1.2E+3` ).
    assert_expr( expr = `-1.2345e3` expected = `(- 1234.5)` ).
    assert_fails( mdx = wrap( `1.2e3.4` ) expected = `Syntax error at line 1, column 38, token '.4'` ).
    assert_expr( expr = `.00234e0003` expected = `2.34` ).
    assert_expr( expr = `.00234e-0067` expected = `2.34E-70` ).
  ENDMETHOD.

  METHOD large_precision.
    assert_query(
      mdx      = `with member [Measures].[Small Number] as '[Measures].[Store Sales] / 9000'\nselect\n`
              && `{[Measures].[Small Number]} on columns,\n`
              && `{Filter([Product].[Product Department].members, [Measures].[Small Number] >= 0.3\n`
              && `and [Measures].[Small Number] <= 0.5000001234)} on rows\nfrom Sales\nwhere ([Time].[1997].[Q2].[4])`
      expected = `with member [Measures].[Small Number] as '([Measures].[Store Sales] / 9000)'\n`
              && `select {[Measures].[Small Number]} ON COLUMNS,\n`
              && `  {Filter([Product].[Product Department].members, (([Measures].[Small Number] >= 0.3) `
              && `AND ([Measures].[Small Number] <= 0.5000001234)))} ON ROWS\n`
              && `from [Sales]\nwhere ([Time].[1997].[Q2].[4])\n` ).
  ENDMETHOD.

  METHOD empty_expr.
    assert_query(
      mdx      = `select NON EMPTY HIERARCHIZE(\n  {DrillDownLevelTop(\n     {[Product].[All Products]},3,,`
              && `[Measures].[Unit Sales])}  ) ON COLUMNS\nfrom [Sales]\n`
      expected = `select NON EMPTY HIERARCHIZE({DrillDownLevelTop({[Product].[All Products]}, 3, , `
              && `[Measures].[Unit Sales])}) ON COLUMNS\nfrom [Sales]\n` ).
    assert_query(
      mdx      = `SELECT {[Measures].[NetSales]} DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON COLUMNS , `
              && `NON EMPTY HIERARCHIZE(AddCalculatedMembers({DrillDownLevelTop({[ProductDim].[Name].[All]}, 10, , `
              && `[Measures].[NetSales])})) DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON ROWS FROM [cube]`
      expected = `select {[Measures].[NetSales]} DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON COLUMNS,\n`
              && `  NON EMPTY HIERARCHIZE(AddCalculatedMembers({DrillDownLevelTop({[ProductDim].[Name].[All]}, 10, , `
              && `[Measures].[NetSales])})) DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON ROWS\nfrom [cube]\n` ).
  ENDMETHOD.

  METHOD as_precedence.
    " ParserTest has FROM cube; CUBE has become a keyword in the reference server's grammar, so the cube is in brackets here
    assert_query( mdx      = `select cast(a and b as string) on 0 from [cube]`
                  expected = `select CAST((a AND b) AS string) ON COLUMNS\nfrom [cube]\n` ).
    assert_query( mdx      = `select cast(a : b as string) on 0 from [cube]`
                  expected = `select CAST((a : b) AS string) ON COLUMNS\nfrom [cube]\n` ).
    assert_query( mdx      = `select cast(a is b as string) on 0 from [cube]`
                  expected = `select CAST((a IS b) AS string) ON COLUMNS\nfrom [cube]\n` ).
    " upstream bug 648 (not fixed): AS has a lower precedence than * and :
    assert_query( mdx = `select a * b as c on 0 from [cube]` expected = `select ((a * b) AS c) ON COLUMNS\nfrom [cube]\n` ).
    assert_fails( mdx = `select a * b as c * d on 0 from [cube]` expected = `Syntax error at line 1, column 19, token '*'` ).
    assert_query( mdx      = `select a : b * c : d on 0 from [cube]`
                  expected = `select ((a : (b * c)) : d) ON COLUMNS\nfrom [cube]\n` ).
    assert_fails( mdx      = `select a : b as n * c : d as n2 as n3 on 0 from [cube]`
                  expected = `Syntax error at line 1, column 19, token '*'` ).
  ENDMETHOD.

  METHOD drill_through.
    assert_query( mdx      = `DRILLTHROUGH SELECT [Foo] on 0, [Bar] on 1 FROM [Cube]`
                  expected = `drillthrough\nselect [Foo] ON COLUMNS,\n  [Bar] ON ROWS\nfrom [Cube]\n` ).
    assert_query( mdx      = `DRILLTHROUGH MAXROWS 5 FIRSTROWSET 7\nSELECT [Foo] on 0, [Bar] on 1 FROM [Cube]\nRETURN [Xxx].[AAa]`
                  expected = `drillthrough maxrows 5 firstrowset 7\nselect [Foo] ON COLUMNS,\n  [Bar] ON ROWS\nfrom [Cube]\n`
                          && ` return  return [Xxx].[AAa]` ).
    assert_query( mdx      = `DRILLTHROUGH MAXROWS 5 FIRSTROWSET 7\nSELECT [Foo] on 0, [Bar] on 1 FROM [Cube]\n`
                          && `RETURN [Xxx].[AAa], [YYY], [zzz]`
                  expected = `drillthrough maxrows 5 firstrowset 7\nselect [Foo] ON COLUMNS,\n  [Bar] ON ROWS\nfrom [Cube]\n`
                          && ` return  return [Xxx].[AAa], [YYY], [zzz]` ).
  ENDMETHOD.

  METHOD explain.
    assert_query( mdx      = `explain plan for\nwith member [Mesaures].[Foo] as 1 + 3\nselect [Measures].[Unit Sales] on 0,\n`
                          && ` [Product].Children on 1\nfrom [Sales]`
                  expected = `explain plan for\nwith member [Mesaures].[Foo] as '(1 + 3)'\n`
                          && `select [Measures].[Unit Sales] ON COLUMNS,\n  [Product].Children ON ROWS\nfrom [Sales]\n` ).
    assert_query( mdx      = `explain plan for\ndrillthrough maxrows 5\nwith member [Mesaures].[Foo] as 1 + 3\n`
                          && `select [Measures].[Unit Sales] on 0,\n [Product].Children on 1\nfrom [Sales]`
                  expected = `explain plan for\ndrillthrough maxrows 5\nwith member [Mesaures].[Foo] as '(1 + 3)'\n`
                          && `select [Measures].[Unit Sales] ON COLUMNS,\n  [Product].Children ON ROWS\nfrom [Sales]\n` ).
  ENDMETHOD.

  METHOD multiple_spaces.
    assert_query( mdx      = `select [Store].[With   multiple  spaces] on 0\nfrom [Sales]`
                  expected = `select [Store].[With   multiple  spaces] ON COLUMNS\nfrom [Sales]\n` ).
  ENDMETHOD.

  METHOD children.
    " .Children in any case is a property call, not a segment of the identifier
    DATA(names) = VALUE string_table( ( `CHILDREN` ) ( `Children` ) ( `children` ) ).
    LOOP AT names INTO DATA(name).
      DATA(node) = zzxxmla1_cl_mdx_parser=>parse_expression( |[Store].[USA].{ name }| ).
      cl_abap_unit_assert=>assert_equals( act = node->kind exp = zzxxmla1_cl_mdx_node=>c_kind-call ).
      cl_abap_unit_assert=>assert_equals( act = node->name exp = name ).
      cl_abap_unit_assert=>assert_equals( act = node->syntax exp = zzxxmla1_cl_mdx_node=>c_syntax-property ).
      cl_abap_unit_assert=>assert_equals( act = lines( node->args ) exp = 1 ).
      cl_abap_unit_assert=>assert_equals( act = node->args[ 1 ]->unparse( ) exp = `[Store].[USA]` ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

"! Error texts and positions as the reference server answers them (captured from the container), for the token manager's rules:
"! the closing newline, tab stops of 8, \r\n, lexical errors at the end of the input, tokens read on demand.
CLASS ltc_reference_errors DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS assert_fails
      IMPORTING mdx      TYPE string
                expected TYPE string.
    METHODS syntax_errors FOR TESTING.
    METHODS lexical_errors FOR TESTING.
    METHODS lexical_errors_at_end FOR TESTING.
    METHODS invalid_axis FOR TESTING.
    METHODS archaic_formula FOR TESTING RAISING zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_reference_errors IMPLEMENTATION.

  METHOD assert_fails.
    TRY.
        zzxxmla1_cl_mdx_parser=>parse( mdx ).
        cl_abap_unit_assert=>fail( |{ mdx }: no error| ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->description exp = expected msg = mdx ).
    ENDTRY.
  ENDMETHOD.

  METHOD syntax_errors.
    DATA(lf) = cl_abap_char_utilities=>newline.
    DATA(cr) = cl_abap_char_utilities=>cr_lf(1).
    DATA(tab) = cl_abap_char_utilities=>horizontal_tab.
    assert_fails( mdx = `select {} on 0 [ZFMSALES]`
                  expected = `olap4abap Error:Syntax error at line 1, column 16, token '[ZFMSALES]'` ).
    " the end of the input is the closing newline
    assert_fails( mdx = `select {} on 0 from` expected = `olap4abap Error:Syntax error at line 1, column 20, token ''` ).
    assert_fails( mdx = |select \{\}{ lf } on{ tab }0 [ZFMSALES]|
                  expected = `olap4abap Error:Syntax error at line 2, column 11, token '[ZFMSALES]'` ).
    assert_fails( mdx = |select \{\}{ cr }{ lf }{ tab }on 0 [ZFMSALES]|
                  expected = `olap4abap Error:Syntax error at line 2, column 14, token '[ZFMSALES]'` ).
    assert_fails( mdx = |select{ tab }{ tab }\{\} on 0 [ZFMSALES]|
                  expected = `olap4abap Error:Syntax error at line 1, column 25, token '[ZFMSALES]'` ).
    assert_fails( mdx = `select {} on -1 from [ZFMSALES]`
                  expected = `olap4abap Error:Syntax error at line 1, column 14, token '-'` ).
    " [ up to the last ] is one name
    assert_fails( mdx = `select [unterminated on 0 from [ZFMSALES]`
                  expected = `olap4abap Error:Syntax error at line 1, column 42, token ''` ).
    assert_fails( mdx = `select x.&[1]. on 0 from [ZFMSALES]`
                  expected = `olap4abap Error:Syntax error at line 1, column 16, token 'on'` ).
    assert_fails( mdx = `selec` expected = `olap4abap Error:Syntax error at line 1, column 1, token 'selec'` ).
    " CUBE is a keyword (REFRESH CUBE, UPDATE CUBE), so a cube of that name needs brackets
    assert_fails( mdx = `select {} on 0 from cube` expected = `olap4abap Error:Syntax error at line 1, column 21, token 'cube'` ).
    assert_fails( mdx = `select 1e on 0 from [ZFMSALES]`
                  expected = `olap4abap Error:Syntax error at line 1, column 9, token 'e'` ).
    assert_fails( mdx = `select 1.2.3 on 0 from x`
                  expected = `olap4abap Error:Syntax error at line 1, column 11, token '.3'` ).
  ENDMETHOD.

  METHOD lexical_errors.
    DATA(lf) = cl_abap_char_utilities=>newline.
    assert_fails( mdx = `select ~ on 0 from [ZFMSALES]`
                  expected = `Lexical error at line 1, column 8.  Encountered: "~" (126), after : ""` ).
    assert_fails( mdx = `select a |x on 0 from [ZFMSALES]`
                  expected = `Lexical error at line 1, column 11.  Encountered: "x" (120), after : "|"` ).
    assert_fails( mdx = `select &~ on 0 from [ZFMSALES]`
                  expected = `Lexical error at line 1, column 9.  Encountered: "~" (126), after : "&"` ).
    assert_fails( mdx = |select [ab{ lf }cd] on 0 from [ZFMSALES]|
                  expected = `Lexical error at line 1, column 11.  Encountered: "\n" (10), after : "[ab"` ).
    assert_fails( mdx = `select {} on 0 from [ZFMSALES];`
                  expected = `Lexical error at line 1, column 31.  Encountered: ";" (59), after : ""` ).
    " tokens are read when the parser needs them: the error after a complete statement is still found
    assert_fails( mdx = `select {} on 0 from [ZFMSALES] where ~`
                  expected = `Lexical error at line 1, column 38.  Encountered: "~" (126), after : ""` ).
    assert_fails( mdx = `select a, b from $system.x ~`
                  expected = `Lexical error at line 1, column 28.  Encountered: "~" (126), after : ""` ).
    assert_fails( mdx = |select äbc on 0 from [ZFMSALES] €|
                  expected = `Lexical error at line 1, column 33.  Encountered: "\` && `u20ac" (8364), after : ""` ).
  ENDMETHOD.

  METHOD lexical_errors_at_end.
    assert_fails( mdx = `select 'abc on 0 from [ZFMSALES]`
                  expected = `Lexical error at line 2, column 0.  Encountered: <EOF> after : "\'abc on 0 from [ZFMSALES]\n"` ).
    assert_fails( mdx = `select {} on 0 from [ZFMSALES] /* open`
                  expected = `Lexical error at line 2, column 0.  Encountered: <EOF> after : ""` ).
    assert_fails( mdx = `select &` expected = `Lexical error at line 2, column 0.  Encountered: <EOF> after : "&\n"` ).
    " /** followed by any character but / opens a comment that */ right behind does not close
    assert_fails( mdx = `/***/ select {} on 0 from [ZFMSALES]`
                  expected = `Lexical error at line 2, column 0.  Encountered: <EOF> after : ""` ).
    " 'a' is a string, the quote behind it opens the next one
    assert_fails( mdx = `select 'a'' on 0 from [ZFMSALES]`
                  expected = `Lexical error at line 2, column 0.  Encountered: <EOF> after : "\' on 0 from [ZFMSALES]\n"` ).
  ENDMETHOD.

  METHOD invalid_axis.
    assert_fails( mdx = `select {} on 1e10 from x`
                  expected = `olap4abap Error:Invalid axis specification. The axis number must be a non-negative integer, `
                          && `but it was 10,000,000,000.` ).
    assert_fails( mdx = `select {} on 1234.5678 from x`
                  expected = `olap4abap Error:Invalid axis specification. The axis number must be a non-negative integer, `
                          && `but it was 1,234.568.` ).
  ENDMETHOD.

  METHOD archaic_formula.
    " the quoted formula is parsed on its own: positions count in the string, the rest after an expression is ignored
    assert_fails( mdx = `with member [Measures].x as '1 +' select from [ZFMSALES]`
                  expected = `olap4abap Error:Syntax error at line 1, column 4, token ''` ).
    DATA(statement) = zzxxmla1_cl_mdx_parser=>parse( `with member [Measures].x as '1 2' select from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = statement-query-formulas[ 1 ]-expression->unparse( ) exp = `1` ).
  ENDMETHOD.

ENDCLASS.

CLASS ltc_parser DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS no_axes FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS axes_and_slicer FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS comments FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS bracket_escape FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS method_call FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS syntax_error FOR TESTING.
ENDCLASS.

CLASS ltc_parser IMPLEMENTATION.
  METHOD no_axes.
    DATA(query) = zzxxmla1_cl_mdx_parser=>parse( `select from [ZFMSALES]` )-query.
    cl_abap_unit_assert=>assert_equals( act = query-cube exp = `ZFMSALES` ).
    cl_abap_unit_assert=>assert_initial( query-axes ).
    cl_abap_unit_assert=>assert_not_bound( query-slicer ).
  ENDMETHOD.

  METHOD axes_and_slicer.
    DATA(query) = zzxxmla1_cl_mdx_parser=>parse(
      `SELECT NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS, {} ON 1 FROM [ZFMSALES] WHERE ([Measures].[Store Cost])` )-query.
    cl_abap_unit_assert=>assert_equals( act = lines( query-axes ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = query-axes[ 1 ]-ordinal exp = 0 ).
    cl_abap_unit_assert=>assert_true( query-axes[ 1 ]-non_empty ).
    cl_abap_unit_assert=>assert_equals( act = query-axes[ 1 ]-expression->syntax exp = `Braces` ).
    cl_abap_unit_assert=>assert_equals( act = query-axes[ 2 ]-ordinal exp = 1 ).
    cl_abap_unit_assert=>assert_initial( query-axes[ 2 ]-expression->args ).
    cl_abap_unit_assert=>assert_equals( act = query-slicer->syntax exp = `Parentheses` ).
    cl_abap_unit_assert=>assert_equals( act = query-slicer->args[ 1 ]->segments[ 2 ]-name exp = `Store Cost` ).
  ENDMETHOD.

  METHOD comments.
    DATA(query) = zzxxmla1_cl_mdx_parser=>parse(
      |-- SELECT x\n/* select y */ // select z\nSELECT \{\} ON ROWS, \{\} ON COLUMNS FROM [C] -- end| )-query.
    cl_abap_unit_assert=>assert_equals( act = lines( query-axes ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = query-cube exp = `C` ).
  ENDMETHOD.

  METHOD bracket_escape.
    DATA(query) = zzxxmla1_cl_mdx_parser=>parse( `select [a [b]] c] on 0 from [C]` )-query.
    cl_abap_unit_assert=>assert_equals( act = query-axes[ 1 ]-expression->segments[ 1 ]-name exp = `a [b] c` ).
  ENDMETHOD.

  METHOD method_call.
    " CurrentMember and Name are property words, so both are calls on what stands before them
    DATA(query) = zzxxmla1_cl_mdx_parser=>parse( `select [Store].CurrentMember.Name on 0 from [C]` )-query.
    DATA(node) = query-axes[ 1 ]-expression.
    cl_abap_unit_assert=>assert_equals( act = node->name exp = `Name` ).
    cl_abap_unit_assert=>assert_equals( act = node->args[ 1 ]->name exp = `CurrentMember` ).
    cl_abap_unit_assert=>assert_equals( act = node->args[ 1 ]->args[ 1 ]->unparse( ) exp = `[Store]` ).
    query = zzxxmla1_cl_mdx_parser=>parse( `select Order([Store].Children, 1, BASC) on 0 from [C]` )-query.
    node = query-axes[ 1 ]-expression.
    cl_abap_unit_assert=>assert_equals( act = node->syntax exp = `Function` ).
    cl_abap_unit_assert=>assert_equals( act = lines( node->args ) exp = 3 ).
  ENDMETHOD.

  METHOD syntax_error.
    TRY.
        zzxxmla1_cl_mdx_parser=>parse( `select {} on 0 [C]` ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
