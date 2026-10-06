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
"! A node of a parsed MDX expression, the counterpart of the reference's parse tree (olap.Exp before validation):
"! - ID is olap.Id: segments, each a name (UNQUOTED foo or QUOTED [foo]) or a KEY (&[k1]&k2, the parts in keys);
"! - CALL is mdx.UnresolvedFunCall: the function name, its syntax as in olap.Syntax (Function,
"!   Property, Method, Infix, Prefix, ...; the receiver of a property or method is the first argument) and the arguments;
"! - LITERAL is olap.Literal: category STRING, NUMERIC, NULL or SYMBOL; a number keeps the text BigDecimal
"!   writes for it (value) and its amount (number).
"! After validation (ZZXXMLA1_CL_MDX_VALIDATOR) the tree holds the reference's resolved expressions instead of IDs and calls:
"! MEMBER, LEVEL, HIERARCHY and DIMENSION are MemberExpr, LevelExpr, HierarchyExpr and DimensionExpr (the element and
"! its unique name in name), RESOLVED_CALL is ResolvedFunCall (the function definition in fun_def); every resolved node
"! has its type (olap.type, ZZXXMLA1_CL_MDX_TYPE). NAMED_SET is NamedSetExpr: a set of the query (WITH SET, a
"! SetBase) or an alias (expression AS name, a Query.ScopedNamedSet, dynamic), with its key within the query and its
"! resolved expression.
"! UNPARSE writes the node back as MDX the way the reference's unparse does.
CLASS zzxxmla1_cl_mdx_node DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_name_segment,
        name    TYPE string,
        quoting TYPE string,
      END OF ty_name_segment,
      ty_t_name_segment TYPE STANDARD TABLE OF ty_name_segment WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_segment,
        name    TYPE string,              " empty for a key segment
        quoting TYPE string,              " UNQUOTED, QUOTED or KEY
        keys    TYPE ty_t_name_segment,   " the parts of a key segment
      END OF ty_segment,
      ty_t_segment TYPE STANDARD TABLE OF ty_segment WITH EMPTY KEY.
    TYPES ty_t_node TYPE STANDARD TABLE OF REF TO zzxxmla1_cl_mdx_node WITH EMPTY KEY.
    CONSTANTS:
      BEGIN OF c_kind,
        id            TYPE string VALUE `ID`,
        call          TYPE string VALUE `CALL`,
        literal       TYPE string VALUE `LITERAL`,
        member        TYPE string VALUE `MEMBER`,
        level         TYPE string VALUE `LEVEL`,
        hierarchy     TYPE string VALUE `HIERARCHY`,
        dimension     TYPE string VALUE `DIMENSION`,
        resolved_call TYPE string VALUE `RESOLVED_CALL`,
        named_set     TYPE string VALUE `NAMED_SET`,
      END OF c_kind,
      BEGIN OF c_quoting,
        unquoted TYPE string VALUE `UNQUOTED`,
        quoted   TYPE string VALUE `QUOTED`,
        key      TYPE string VALUE `KEY`,
      END OF c_quoting,
      BEGIN OF c_syntax,
        function                  TYPE string VALUE `Function`,
        property                  TYPE string VALUE `Property`,
        method                    TYPE string VALUE `Method`,
        infix                     TYPE string VALUE `Infix`,
        prefix                    TYPE string VALUE `Prefix`,
        postfix                   TYPE string VALUE `Postfix`,
        braces                    TYPE string VALUE `Braces`,
        parentheses               TYPE string VALUE `Parentheses`,
        case                      TYPE string VALUE `Case`,
        cast                      TYPE string VALUE `Cast`,
        quoted_property           TYPE string VALUE `QuotedProperty`,
        ampersand_quoted_property TYPE string VALUE `AmpersandQuotedProperty`,
        empty                     TYPE string VALUE `Empty`,
      END OF c_syntax,
      BEGIN OF c_category,
        string  TYPE string VALUE `STRING`,
        numeric TYPE string VALUE `NUMERIC`,
        null    TYPE string VALUE `NULL`,
        symbol  TYPE string VALUE `SYMBOL`,
      END OF c_category.

    DATA kind     TYPE string READ-ONLY.
    DATA segments TYPE ty_t_segment READ-ONLY.   " ID
    DATA name     TYPE string READ-ONLY.         " CALL: the function name
    DATA syntax   TYPE string READ-ONLY.         " CALL
    DATA args     TYPE ty_t_node READ-ONLY.      " CALL
    DATA category TYPE string READ-ONLY.         " LITERAL
    DATA value    TYPE string READ-ONLY.         " LITERAL: the string, the symbol or the number as BigDecimal writes it
    DATA number   TYPE decfloat34 READ-ONLY.     " LITERAL: the number
    TYPES:
      "! FunDef: the function a call was resolved to.
      BEGIN OF ty_fun_def,
        name                 TYPE string,
        syntax               TYPE string,
        return_category      TYPE i,
        parameter_categories TYPE zzxxmla1_cl_mdx_funtable=>ty_t_category,
        "! the parameter categories of the signature that matched (a MultiResolver's FunDef takes the categories of
        "! the arguments as parameter_categories)
        signature_categories TYPE zzxxmla1_cl_mdx_funtable=>ty_t_category,
        resolver_kind        TYPE string,
        resolver_id          TYPE i,
        "! the FunDef class where the resolver has logic of its own (SetFunDef, TupleFunDef, ParenthesesFunDef,
        "! CrossJoinFunDef); empty for the resolvers that resolve by their signatures
        implementation       TYPE string,
        signature            TYPE string,        " FunDef.getSignature
      END OF ty_fun_def.
    DATA type     TYPE REF TO zzxxmla1_cl_mdx_type READ-ONLY.          " resolved nodes
    DATA element  TYPE zzxxmla1_cl_mdx_schema_reader=>ty_element READ-ONLY. " MEMBER, LEVEL, HIERARCHY, DIMENSION
    DATA fun_def  TYPE ty_fun_def READ-ONLY.     " RESOLVED_CALL
    DATA set_key        TYPE string READ-ONLY.                       " NAMED_SET: unique within the query
    DATA set_expression TYPE REF TO zzxxmla1_cl_mdx_node READ-ONLY.  " NAMED_SET: the resolved expression
    DATA set_dynamic    TYPE abap_bool READ-ONLY.                    " NAMED_SET: an alias (NamedSet.isDynamic)

    "! MemberExpr, LevelExpr, HierarchyExpr, DimensionExpr: kind as c_kind, name the unique name of the element.
    CLASS-METHODS create_element
      IMPORTING kind          TYPE string
                element       TYPE zzxxmla1_cl_mdx_schema_reader=>ty_element
                name          TYPE string
                type          TYPE REF TO zzxxmla1_cl_mdx_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    "! NamedSetExpr: name is the unique name ([name] of a WITH SET, the name of an alias).
    CLASS-METHODS create_named_set
      IMPORTING name          TYPE string
                key           TYPE string
                expression    TYPE REF TO zzxxmla1_cl_mdx_node
                dynamic       TYPE abap_bool
                type          TYPE REF TO zzxxmla1_cl_mdx_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    "! ResolvedFunCall.
    CLASS-METHODS create_resolved_call
      IMPORTING fun_def       TYPE ty_fun_def
                args          TYPE ty_t_node
                type          TYPE REF TO zzxxmla1_cl_mdx_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    "! Exp.getType: the type of a resolved node; a literal's type follows from its category (Literal.getType).
    METHODS get_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.

    CLASS-METHODS create_id
      IMPORTING segments      TYPE ty_t_segment
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    CLASS-METHODS create_call
      IMPORTING name          TYPE string
                syntax        TYPE string
                args          TYPE ty_t_node OPTIONAL
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    CLASS-METHODS create_string
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    CLASS-METHODS create_symbol
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    CLASS-METHODS create_null
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    "! A numeric literal from its MDX text, as new BigDecimal(text): the digits without the point are the unscaled
    "! value, the decimals less the exponent the scale.
    CLASS-METHODS create_numeric
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    "! [name] with ] doubled, as Util.quoteMdxIdentifier.
    CLASS-METHODS quote_identifier
      IMPORTING name          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! A segment as MDX, as Id.Segment.toString.
    CLASS-METHODS unparse_segment
      IMPORTING segment       TYPE ty_segment
      RETURNING VALUE(result) TYPE string.

    "! A new ID with the segment after the segments of this one (Id.append).
    METHODS append
      IMPORTING segment       TYPE ty_segment
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_node.
    METHODS unparse
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    "! The text of BigDecimal.toString for an unscaled value (digits, no leading zeros) and a scale.
    CLASS-METHODS big_decimal_text
      IMPORTING unscaled      TYPE string
                scale         TYPE i
      RETURNING VALUE(result) TYPE string.
    METHODS unparse_list
      IMPORTING first         TYPE i DEFAULT 1
                start         TYPE string
                mid           TYPE string
                end           TYPE string
      RETURNING VALUE(result) TYPE string.
    "! Syntax.needParen: an operator gets parentheses unless its only argument is a parenthesized expression.
    METHODS need_paren
      RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_node IMPLEMENTATION.

  METHOD create_id.
    result = NEW #( ).
    result->kind = c_kind-id.
    result->segments = segments.
  ENDMETHOD.

  METHOD create_call.
    result = NEW #( ).
    result->kind = c_kind-call.
    result->name = name.
    result->syntax = syntax.
    result->args = args.
  ENDMETHOD.

  METHOD create_element.
    result = NEW #( ).
    result->kind = kind.
    result->element = element.
    result->name = name.
    result->type = type.
  ENDMETHOD.

  METHOD create_named_set.
    result = NEW #( ).
    result->kind = c_kind-named_set.
    result->name = name.
    result->set_key = key.
    result->set_expression = expression.
    result->set_dynamic = dynamic.
    result->type = type.
  ENDMETHOD.

  METHOD create_resolved_call.
    result = NEW #( ).
    result->kind = c_kind-resolved_call.
    result->fun_def = fun_def.
    result->name = fun_def-name.
    result->syntax = fun_def-syntax.
    result->args = args.
    result->type = type.
  ENDMETHOD.

  METHOD get_type.
    IF type IS BOUND OR kind <> c_kind-literal.
      result = type.
      RETURN.
    ENDIF.
    result = SWITCH #( category WHEN c_category-symbol THEN zzxxmla1_cl_mdx_type=>symbol( )
                                WHEN c_category-numeric THEN zzxxmla1_cl_mdx_type=>numeric( )
                                WHEN c_category-string THEN zzxxmla1_cl_mdx_type=>string( )
                                ELSE zzxxmla1_cl_mdx_type=>null( ) ).
  ENDMETHOD.

  METHOD create_string.
    result = NEW #( ).
    result->kind = c_kind-literal.
    result->category = c_category-string.
    result->value = value.
  ENDMETHOD.

  METHOD create_symbol.
    result = NEW #( ).
    result->kind = c_kind-literal.
    result->category = c_category-symbol.
    result->value = value.
  ENDMETHOD.

  METHOD create_null.
    result = NEW #( ).
    result->kind = c_kind-literal.
    result->category = c_category-null.
  ENDMETHOD.

  METHOD create_numeric.
    DATA(upper) = to_upper( text ).
    DATA(mantissa) = upper.
    DATA(exponent) = 0.
    IF upper CS `E`.
      SPLIT upper AT `E` INTO mantissa DATA(exponent_text).
      exponent = exponent_text.
    ENDIF.
    SPLIT mantissa AT `.` INTO DATA(integer_part) DATA(fraction_part).
    DATA(unscaled) = shift_left( val = integer_part && fraction_part sub = `0` ).
    IF unscaled IS INITIAL.
      unscaled = `0`.
    ENDIF.
    DATA(scale) = strlen( fraction_part ) - exponent.

    result = NEW #( ).
    result->kind = c_kind-literal.
    result->category = c_category-numeric.
    result->value = big_decimal_text( unscaled = unscaled scale = scale ).
    DATA(amount) = CONV decfloat34( unscaled ).
    DO abs( scale ) TIMES.
      amount = COND #( WHEN scale > 0 THEN amount / 10 ELSE amount * 10 ).
    ENDDO.
    result->number = amount.
  ENDMETHOD.

  METHOD big_decimal_text.
    DATA(length) = strlen( unscaled ).
    DATA(adjusted) = length - 1 - scale.
    IF scale >= 0 AND adjusted >= -6.
      IF scale = 0.
        result = unscaled.
      ELSEIF length > scale.
        result = |{ substring( val = unscaled len = length - scale ) }.{ substring( val = unscaled off = length - scale ) }|.
      ELSE.
        result = |0.{ repeat( val = `0` occ = scale - length ) }{ unscaled }|.
      ENDIF.
    ELSE.
      result = substring( val = unscaled len = 1 ).
      IF length > 1.
        result = |{ result }.{ substring( val = unscaled off = 1 ) }|.
      ENDIF.
      result = |{ result }E{ COND #( WHEN adjusted >= 0 THEN `+` ) }{ adjusted }|.
    ENDIF.
  ENDMETHOD.

  METHOD quote_identifier.
    result = |[{ replace( val = name sub = `]` with = `]]` occ = 0 ) }]|.
  ENDMETHOD.

  METHOD unparse_segment.
    CASE segment-quoting.
      WHEN c_quoting-unquoted.
        result = segment-name.
      WHEN c_quoting-quoted.
        result = quote_identifier( segment-name ).
      WHEN OTHERS.
        LOOP AT segment-keys INTO DATA(key).
          result = result && `&` && unparse_segment( VALUE #( name = key-name quoting = key-quoting ) ).
        ENDLOOP.
    ENDCASE.
  ENDMETHOD.

  METHOD append.
    DATA(extended) = segments.
    APPEND segment TO extended.
    result = create_id( extended ).
  ENDMETHOD.

  METHOD unparse.
    CASE kind.
      WHEN c_kind-id.
        LOOP AT segments INTO DATA(segment).
          result = result && COND #( WHEN sy-tabix > 1 THEN `.` ) && unparse_segment( segment ).
        ENDLOOP.
      WHEN c_kind-literal.
        CASE category.
          WHEN c_category-string.
            result = |"{ replace( val = value sub = `"` with = `""` occ = 0 ) }"|.
          WHEN c_category-null.
            result = `NULL`.
          WHEN OTHERS.
            result = value.
        ENDCASE.
      WHEN c_kind-member OR c_kind-level OR c_kind-hierarchy OR c_kind-dimension OR c_kind-named_set.
        result = name.
      WHEN c_kind-call OR c_kind-resolved_call.
        CASE syntax.
          WHEN c_syntax-function.
            result = unparse_list( start = name && `(` mid = `, ` end = `)` ).
          WHEN c_syntax-property.
            result = |{ args[ 1 ]->unparse( ) }.{ name }|.
          WHEN c_syntax-quoted_property OR c_syntax-ampersand_quoted_property.
            " The reference has no unparse for these; written as the segment they came from
            result = |{ args[ 1 ]->unparse( ) }.{ quote_identifier( name ) }|.
          WHEN c_syntax-method.
            result = |{ args[ 1 ]->unparse( ) }.{ name }{ unparse_list( first = 2 start = `(` mid = `, ` end = `)` ) }|.
          WHEN c_syntax-infix.
            IF need_paren( ) = abap_true.
              result = unparse_list( start = `(` mid = | { name } | end = `)` ).
            ELSE.
              result = unparse_list( start = `` mid = | { name } | end = `` ).
            ENDIF.
          WHEN c_syntax-prefix.
            IF need_paren( ) = abap_true.
              result = unparse_list( start = |({ name } | mid = `` end = `)` ).
            ELSE.
              result = unparse_list( start = |{ name } | mid = `` end = `` ).
            ENDIF.
          WHEN c_syntax-postfix.
            IF need_paren( ) = abap_true.
              result = unparse_list( start = `(` mid = `` end = | { name })| ).
            ELSE.
              result = unparse_list( start = `` mid = `` end = | { name }| ).
            ENDIF.
          WHEN c_syntax-braces.
            result = unparse_list( start = `{` mid = `, ` end = `}` ).
          WHEN c_syntax-parentheses.
            result = unparse_list( start = `(` mid = `, ` end = `)` ).
          WHEN c_syntax-case.
            DATA(next) = 1.
            IF name = `_CaseTest`.
              result = `CASE`.
            ELSE.
              result = |CASE { args[ 1 ]->unparse( ) }|.
              next = 2.
            ENDIF.
            WHILE next + 1 <= lines( args ).
              result = |{ result } WHEN { args[ next ]->unparse( ) } THEN { args[ next + 1 ]->unparse( ) }|.
              next = next + 2.
            ENDWHILE.
            IF next <= lines( args ).
              result = |{ result } ELSE { args[ next ]->unparse( ) }|.
            ENDIF.
            result = |{ result } END|.
          WHEN c_syntax-cast.
            result = |CAST({ args[ 1 ]->unparse( ) } AS { args[ 2 ]->unparse( ) })|.
          WHEN c_syntax-empty.
            result = ``.
        ENDCASE.
    ENDCASE.
  ENDMETHOD.

  METHOD unparse_list.
    result = start.
    LOOP AT args INTO DATA(arg) FROM first.
      IF sy-tabix > first.
        result = result && mid.
      ENDIF.
      result = result && arg->unparse( ).
    ENDLOOP.
    result = result && end.
  ENDMETHOD.

  METHOD need_paren.
    result = xsdbool( NOT ( lines( args ) = 1 AND args[ 1 ]->kind = c_kind-call
                            AND args[ 1 ]->syntax = c_syntax-parentheses ) ).
  ENDMETHOD.

ENDCLASS.
