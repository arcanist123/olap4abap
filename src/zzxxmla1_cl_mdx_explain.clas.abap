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
"! The explanation of an executed query, our addition (the reference has none): the resolved tree of its formulas,
"! axes, slicer and subselects (ZZXXMLA1_CL_MDX_VALIDATOR), each node with its kind, its type, its MDX and its mark of
"! the plan (ZZXXMLA1_CL_MDX_PLANNER: static, relational, computed), and the plan of the query. Every node has a
"! number; while ZZXXMLA1_CL_MDX_ENGINE evaluates a node it sets ZZXXMLA1_CL_SQL=>log_node to it, so each logged
"! statement names the node that read it (and log_phase the phase: the slicer, an axis, the cells). The engine
"! explains a query only while statements are logged (the trace of a call, ZZXXMLA1_CL_TRACE, keeps the explanation
"! with them; the MDX console shows both). The explanation is JSON:
"! {"cube":..,"plan":{"query":..,"slicer":..,"cells":..},"parts":[{"part":"formula"|"axis"|"slicer"|"subcube",
"! "label":..,"mark":..,"node":{"id":..,"kind":..,"label":..,"type":..,"mark":..,"mdx":..,"args":[..]}}]}
"! A named set's expression is a child of the first node that names it; later ones refer to it (ref, its id).
CLASS zzxxmla1_cl_mdx_explain DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES ty_node TYPE REF TO zzxxmla1_cl_mdx_node.
    TYPES:
      "! a node and its number in the explanation
      BEGIN OF ty_node_id,
        node TYPE ty_node,
        id   TYPE i,
      END OF ty_node_id,
      ty_t_node_id TYPE HASHED TABLE OF ty_node_id WITH UNIQUE KEY node.

    "! The explanation of the last query explained since clear (JSON); empty if there is none.
    CLASS-DATA last TYPE string READ-ONLY.

    "! Forgets the last explanation (the trace of a call starts with it).
    CLASS-METHODS clear.
    "! Explains a resolved query into last.
    "! @parameter planner | the planner of the query, after plan
    "! @parameter plan | the plan of the query
    "! @parameter result | the number of each node, for ZZXXMLA1_CL_SQL=>log_node
    CLASS-METHODS explain
      IMPORTING query         TYPE zzxxmla1_cl_mdx_parser=>ty_query
                cube          TYPE string
                planner       TYPE REF TO zzxxmla1_cl_mdx_planner
                plan          TYPE zzxxmla1_cl_mdx_planner=>ty_plan
      RETURNING VALUE(result) TYPE ty_t_node_id.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! how much of a node's MDX is kept (a node's text holds those of its arguments)
    CONSTANTS c_mdx_length TYPE i VALUE 1000.

    DATA planner TYPE REF TO zzxxmla1_cl_mdx_planner.
    DATA ids TYPE ty_t_node_id.

    METHODS constructor
      IMPORTING planner TYPE REF TO zzxxmla1_cl_mdx_planner.
    "! A node and its arguments as JSON; numbered on the way.
    METHODS node_json
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE string.
    "! What a node shows in the tree: the function, the element's unique name, the literal, the set's name.
    CLASS-METHODS label
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE string.
    "! A part of the query (formula, axis, slicer, subcube) as JSON.
    METHODS part_json
      IMPORTING part          TYPE string
                !label        TYPE string
                node          TYPE ty_node
                children      TYPE string_table OPTIONAL
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS json
      IMPORTING !value        TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_mdx_explain IMPLEMENTATION.

  METHOD clear.
    CLEAR last.
  ENDMETHOD.

  METHOD explain.
    DATA(explainer) = NEW zzxxmla1_cl_mdx_explain( planner ).
    DATA(parts) = VALUE string_table( ).
    LOOP AT query-formulas INTO DATA(formula).
      DATA(properties) = VALUE string_table( ).
      LOOP AT formula-properties INTO DATA(property).
        APPEND explainer->part_json( part = `property` label = property-name node = property-expression ) TO properties.
      ENDLOOP.
      APPEND explainer->part_json( part     = `formula`
                                   label    = |{ COND #( WHEN formula-is_member = abap_true THEN `MEMBER` ELSE `SET` ) } {
                                               formula-name->unparse( ) }|
                                   node     = formula-expression
                                   children = properties ) TO parts.
    ENDLOOP.
    LOOP AT query-subcubes INTO DATA(subcube) WHERE axes IS NOT INITIAL.
      LOOP AT subcube-axes INTO DATA(subcube_axis).
        APPEND explainer->part_json( part  = `subcube`
                                     label = |Subselect { zzxxmla1_cl_mdx_parser=>axis_name( subcube_axis-ordinal ) }|
                                     node  = subcube_axis-expression ) TO parts.
      ENDLOOP.
      IF subcube-slicer IS BOUND.
        APPEND explainer->part_json( part = `subcube` label = `Subselect WHERE` node = subcube-slicer ) TO parts.
      ENDIF.
    ENDLOOP.
    IF query-slicer IS BOUND.
      APPEND explainer->part_json( part = `slicer` label = `WHERE` node = query-slicer ) TO parts.
    ENDIF.
    LOOP AT query-axes INTO DATA(axis).
      APPEND explainer->part_json(
          part  = `axis`
          label = |{ COND #( WHEN axis-non_empty = abap_true THEN `NON EMPTY ` ) }{
                  zzxxmla1_cl_mdx_parser=>axis_name( axis-ordinal ) } (Axis{ axis-ordinal })|
          node  = axis-expression ) TO parts.
    ENDLOOP.
    DATA(axes) = VALUE string_table( FOR a IN plan-axes ( json( a-mark ) ) ).
    last = |\{"cube":{ json( cube ) },"plan":\{"query":{ json( plan-query ) },"slicer":{ json( plan-slicer ) },| &&
           |"cells":{ json( plan-cells ) },"axes":[{ concat_lines_of( table = axes sep = `,` ) }]\},| &&
           |"parts":[{ concat_lines_of( table = parts sep = `,` ) }]\}|.
    result = explainer->ids.
  ENDMETHOD.

  METHOD constructor.
    me->planner = planner.
  ENDMETHOD.

  METHOD part_json.
    DATA(tree) = COND string( WHEN node IS BOUND THEN node_json( node ) ELSE `null` ).
    result = |\{"part":{ json( part ) },"label":{ json( label ) },"node":{ tree }| &&
             |{ COND #( WHEN children IS NOT INITIAL THEN |,"children":[{ concat_lines_of( table = children sep = `,` ) }]| ) }\}|.
  ENDMETHOD.

  METHOD node_json.
    READ TABLE ids INTO DATA(known) WITH TABLE KEY node = node.
    IF sy-subrc = 0.
      " a node met again (a named set named twice): a reference to the first
      result = |\{"ref":{ known-id },"label":{ json( label( node ) ) }\}|.
      RETURN.
    ENDIF.
    DATA(id) = lines( ids ) + 1.
    INSERT VALUE #( node = node id = id ) INTO TABLE ids.

    DATA(args) = VALUE string_table( ).
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-named_set AND node->set_expression IS BOUND.
      APPEND node_json( node->set_expression ) TO args.
    ELSE.
      LOOP AT node->args INTO DATA(arg) WHERE table_line IS BOUND.
        APPEND node_json( arg ) TO args.
      ENDLOOP.
    ENDIF.
    DATA(node_type) = node->get_type( ).
    DATA(type) = COND string( WHEN node_type IS BOUND THEN node_type->kind ).
    DATA(mdx) = node->unparse( ).
    IF strlen( mdx ) > c_mdx_length.
      mdx = substring( val = mdx len = c_mdx_length ) && `...`.
    ENDIF.
    result = |\{"id":{ id },"kind":{ json( node->kind ) },"label":{ json( label( node ) ) },"type":{ json( type ) },| &&
             |"mark":{ json( planner->get_mark( node ) ) },"mdx":{ json( mdx ) },| &&
             |"args":[{ concat_lines_of( table = args sep = `,` ) }]\}|.
  ENDMETHOD.

  METHOD label.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
        result = SWITCH #( node->fun_def-implementation
                           WHEN `SetFunDef` THEN `{ }`
                           WHEN `ParenthesesFunDef` THEN `( )`
                           WHEN `TupleFunDef` THEN `( , )`
                           ELSE node->fun_def-name ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-literal.
        result = COND #( WHEN node->category = zzxxmla1_cl_mdx_node=>c_category-string THEN |"{ node->value }"|
                         WHEN node->category = zzxxmla1_cl_mdx_node=>c_category-null THEN `NULL`
                         ELSE node->value ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-call.
        result = node->name.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-id.
        result = node->unparse( ).
      WHEN OTHERS.
        " MEMBER, LEVEL, HIERARCHY, DIMENSION: the unique name; NAMED_SET: its name
        result = node->name.
    ENDCASE.
  ENDMETHOD.

  METHOD json.
    result = |"{ escape( val = value format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.

ENDCLASS.
