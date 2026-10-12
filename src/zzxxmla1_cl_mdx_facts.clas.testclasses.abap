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
"! The facts of ZFMSALES (FoodMart 1997).
CLASS ltc_facts DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    DATA facts TYPE REF TO zzxxmla1_cl_mdx_facts.
    DATA unit_sales TYPE i.
    METHODS setup RAISING zzxxmla1_cx_xmla.
    METHODS teardown.
    METHODS non_empty_paths FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS batching FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS max_constraints FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS without_batching FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS top_count FOR TESTING RAISING zzxxmla1_cx_xmla.
    "! the filter of a product family
    METHODS family
      IMPORTING name          TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_facts=>ty_t_filter
      RAISING   zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_facts IMPLEMENTATION.

  METHOD setup.
    reader = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
    facts = NEW zzxxmla1_cl_mdx_facts( cube = reader->cube hierarchies = reader->get_model_hierarchies( )
                                       measures = reader->measures ).
    unit_sales = line_index( reader->measures[ name = `Unit Sales` ] ).
  ENDMETHOD.

  METHOD teardown.
    zzxxmla1_cl_mdx_facts=>max_constraints = 1000.
  ENDMETHOD.

  METHOD family.
    DATA(member) = reader->lookup_compound( VALUE #( ( name = `Product` quoting = `QUOTED` )
                                                     ( name = name quoting = `QUOTED` ) ) )-member.
    result = VALUE #( ( hierarchy = member-hier_id level = member-key_level path = member-path ) ).
  ENDMETHOD.

  METHOD batching.
    " FastBatchingCellReader: a cell not read yet is 0 for the pass, recorded, and read by load_aggregations
    facts->set_batching( abap_true ).
    DATA(drink) = facts->value( filters = family( `Drink` ) measure = unit_sales ).
    cl_abap_unit_assert=>assert_false( drink-empty ).
    cl_abap_unit_assert=>assert_equals( act = drink-amount exp = 0 ).
    cl_abap_unit_assert=>assert_true( facts->is_dirty( ) ).
    facts->value( filters = family( `Food` ) measure = unit_sales ).
    cl_abap_unit_assert=>assert_equals( act = facts->get_miss_count( ) exp = 2 ).
    cl_abap_unit_assert=>assert_true( facts->load_aggregations( ) ).
    cl_abap_unit_assert=>assert_false( facts->is_dirty( ) ).
    cl_abap_unit_assert=>assert_false( facts->load_aggregations( ) ).
    cl_abap_unit_assert=>assert_equals( act = facts->value( filters = family( `Drink` ) measure = unit_sales )-amount
                                        exp = 24597 ).
    cl_abap_unit_assert=>assert_equals( act = facts->value( filters = family( `Food` ) measure = unit_sales )-amount
                                        exp = 191940 ).
    " the load was constrained to the families asked for: Non-Consumable is not read yet
    facts->value( filters = family( `Non-Consumable` ) measure = unit_sales ).
    cl_abap_unit_assert=>assert_true( facts->is_dirty( ) ).
    cl_abap_unit_assert=>assert_equals( act = facts->get_miss_count( ) exp = 3 ).
    facts->load_aggregations( ).
    cl_abap_unit_assert=>assert_equals(
      act = facts->value( filters = family( `Non-Consumable` ) measure = unit_sales )-amount exp = 50236 ).
    cl_abap_unit_assert=>assert_equals( act = facts->get_miss_count( ) exp = 3 ).
  ENDMETHOD.

  METHOD max_constraints.
    " more keys than max_constraints: the column is not constrained, so the other families are read too
    zzxxmla1_cl_mdx_facts=>max_constraints = 1.
    facts->set_batching( abap_true ).
    facts->value( filters = family( `Drink` ) measure = unit_sales ).
    facts->value( filters = family( `Food` ) measure = unit_sales ).
    facts->load_aggregations( ).
    cl_abap_unit_assert=>assert_equals( act = facts->value( filters = family( `Drink` ) measure = unit_sales )-amount
                                        exp = 24597 ).
    cl_abap_unit_assert=>assert_equals( act = facts->value( filters = family( `Food` ) measure = unit_sales )-amount
                                        exp = 191940 ).
    cl_abap_unit_assert=>assert_equals(
      act = facts->value( filters = family( `Non-Consumable` ) measure = unit_sales )-amount exp = 50236 ).
    cl_abap_unit_assert=>assert_false( facts->is_dirty( ) ).
    cl_abap_unit_assert=>assert_equals( act = facts->get_miss_count( ) exp = 2 ).
  ENDMETHOD.

  METHOD without_batching.
    " a missed cell is read at once; one without facts is empty, and known afterwards
    cl_abap_unit_assert=>assert_equals( act = facts->value( filters = family( `Drink` ) measure = unit_sales )-amount
                                        exp = 24597 ).
    cl_abap_unit_assert=>assert_false( facts->is_dirty( ) ).
    DATA(none) = family( `Drink` ).
    none[ 1 ]-path = `999999999`.
    cl_abap_unit_assert=>assert_true( facts->value( filters = none measure = unit_sales )-empty ).
    cl_abap_unit_assert=>assert_true( facts->value( filters = none measure = unit_sales )-empty ).
    cl_abap_unit_assert=>assert_equals( act = facts->get_miss_count( ) exp = 2 ).
  ENDMETHOD.

  METHOD top_count.
    DATA(level) = reader->get_level( reader->lookup_compound( VALUE #( ( name = `Product` quoting = `QUOTED` )
                                                                      ( name = `Product Family` quoting = `QUOTED` ) ) )-id ).
    DATA(operands) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_top_operand( ( hierarchy = level-hierarchy
                                                                      level     = level-key_level ) ).
    " the families: Drink, Food, Non-Consumable and the unassigned one (empty key, no facts)
    cl_abap_unit_assert=>assert_equals( act = facts->operand_counts( operands )
                                        exp = VALUE zzxxmla1_cl_mdx_facts=>ty_t_count( ( CONV #( 4 ) ) ) ).
    DATA(filters) = family( `Drink` ).
    DATA(drink) = filters[ 1 ]-path.
    filters = family( `Food` ).
    DATA(food) = filters[ 1 ]-path.
    filters = family( `Non-Consumable` ).
    DATA(non_consumable) = filters[ 1 ]-path.
    " by unit sales, the empty family last
    cl_abap_unit_assert=>assert_equals(
      act = facts->top_count( operands = operands filters = VALUE #( ) measure = unit_sales count = 4 top = abap_true
                              with_empty = abap_true )
      exp = VALUE zzxxmla1_cl_mdx_facts=>ty_t_paths( ( VALUE #( ( food ) ) ) ( VALUE #( ( non_consumable ) ) )
                                                     ( VALUE #( ( drink ) ) ) ( VALUE #( ( `` ) ) ) ) ).
    " BottomCount: the empty family first
    cl_abap_unit_assert=>assert_equals(
      act = facts->top_count( operands = operands filters = VALUE #( ) measure = unit_sales count = 2 top = abap_false
                              with_empty = abap_true )
      exp = VALUE zzxxmla1_cl_mdx_facts=>ty_t_paths( ( VALUE #( ( `` ) ) ) ( VALUE #( ( drink ) ) ) ) ).
    " without the empty tuples
    cl_abap_unit_assert=>assert_equals(
      act = lines( facts->top_count( operands = operands filters = VALUE #( ) measure = unit_sales count = 4
                                     top = abap_true with_empty = abap_false ) )
      exp = 3 ).
  ENDMETHOD.

  METHOD non_empty_paths.
    DATA(family) = reader->lookup_compound( VALUE #( ( name = `Product` quoting = `QUOTED` )
                                                     ( name = `Product Family` quoting = `QUOTED` ) ) ).
    DATA(level) = reader->get_level( family-id ).
    " the product families with facts: Drink, Food, Non-Consumable (the unassigned one, empty key, has none)
    DATA(paths) = facts->non_empty_paths( VALUE #( ( hierarchy = level-hierarchy level = level-key_level
                                                     any = abap_true ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( paths ) exp = 3 ).
    DATA(drink) = reader->lookup_compound( VALUE #( ( name = `Product` quoting = `QUOTED` )
                                                    ( name = `Drink` quoting = `QUOTED` ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( paths[ table_line = VALUE #( ( drink-member-path ) ) ] ) ) ).
    " with a context: the families sold in January 1997
    DATA(january) = reader->lookup_compound( VALUE #( ( name = `Time` quoting = `QUOTED` )
                                                      ( name = `1997` quoting = `QUOTED` )
                                                      ( name = `Q1` quoting = `QUOTED` )
                                                      ( name = `1` quoting = `QUOTED` ) ) ).
    paths = facts->non_empty_paths( VALUE #( ( hierarchy = january-member-hier_id level = january-member-key_level
                                               path = january-member-path )
                                             ( hierarchy = level-hierarchy level = level-key_level any = abap_true ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( paths ) exp = 3
      msg = |{ january-member-hier_id }:{ january-member-key_level }:{ replace( val = january-member-path sub = cl_abap_char_utilities=>horizontal_tab with = `/` occ = 0 ) }| ).
    " ... and the customers of the USA (a hierarchy before the product's)
    DATA(usa) = reader->lookup_compound( VALUE #( ( name = `Customers` quoting = `QUOTED` )
                                                  ( name = `USA` quoting = `QUOTED` ) ) ).
    paths = facts->non_empty_paths( VALUE #( ( hierarchy = usa-member-hier_id level = usa-member-key_level
                                               path = usa-member-path )
                                             ( hierarchy = level-hierarchy level = level-key_level any = abap_true ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( paths ) exp = 3
      msg = |{ usa-member-hier_id }:{ usa-member-key_level }:{ usa-member-path } product { level-hierarchy }| ).
  ENDMETHOD.

ENDCLASS.
