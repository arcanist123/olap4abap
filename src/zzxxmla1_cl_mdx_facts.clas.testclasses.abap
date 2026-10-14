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
    METHODS ordered_paths FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS grouping_sets FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS slicer_predicate FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS roll_up FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS defaults FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS unconstrained_set FOR TESTING RAISING zzxxmla1_cx_xmla.
    "! the pattern of a level of a member's hierarchy, with the paths asked for
    METHODS pattern
      IMPORTING filter        TYPE zzxxmla1_cl_mdx_facts=>ty_filter
                paths         TYPE string_table
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_facts=>ty_cross_pattern.
    "! the first quarter of 1997
    METHODS quarter
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_facts=>ty_filter
      RAISING   zzxxmla1_cx_xmla.
    "! the filter of a state of the USA in Store
    METHODS state
      IMPORTING name          TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_facts=>ty_t_filter
      RAISING   zzxxmla1_cx_xmla.
    "! the unit sales of the groups of a pattern of cross_values, by their paths
    "! @parameter only | the groups of these paths only (each the paths of its filters joined by /); all if empty
    METHODS sales_of
      IMPORTING values        TYPE zzxxmla1_cl_mdx_facts=>ty_t_cross_value
                pattern       TYPE i
                only          TYPE string_table OPTIONAL
      RETURNING VALUE(result) TYPE string_table.
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

  METHOD state.
    DATA(member) = reader->lookup_compound( VALUE #( ( name = `Store` quoting = `QUOTED` )
                                                     ( name = `USA` quoting = `QUOTED` )
                                                     ( name = name quoting = `QUOTED` ) ) )-member.
    result = VALUE #( ( hierarchy = member-hier_id level = member-key_level path = member-path ) ).
  ENDMETHOD.

  METHOD sales_of.
    LOOP AT values INTO DATA(value) WHERE pattern = pattern.
      DATA(paths) = concat_lines_of( table = value-paths sep = `/` ).
      IF only IS INITIAL OR line_exists( only[ table_line = paths ] ).
        APPEND |{ paths }={ value-amounts[ unit_sales ] }| TO result.
      ENDIF.
    ENDLOOP.
    SORT result.
  ENDMETHOD.

  METHOD grouping_sets.
    " the families Drink and Food, the All member, and Drink's departments: one GROUPING SETS statement
    DATA(drink) = family( `Drink` ).
    DATA(food) = family( `Food` ).
    DATA(patterns) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_cross_pattern(
      ( filters = VALUE #( ( hierarchy = drink[ 1 ]-hierarchy level = 1 ) )
        paths   = VALUE #( ( VALUE #( ( drink[ 1 ]-path ) ( food[ 1 ]-path ) ) ) ) )
      ( )
      ( filters = VALUE #( ( hierarchy = drink[ 1 ]-hierarchy level = 2 ) )
        paths   = VALUE #( ( VALUE #( ( |{ drink[ 1 ]-path }{ zzxxmla1_cl_model=>c_separator }Beverages| ) ) ) ) ) ).
    DATA(grouped) = facts->cross_values( patterns ).
    " the families asked for only: Non-Consumable is read for the All member's set but not kept for this one
    cl_abap_unit_assert=>assert_equals( act = sales_of( values = grouped pattern = 1 )
                                        exp = VALUE string_table( ( |{ drink[ 1 ]-path }=24597| )
                                                                  ( |{ food[ 1 ]-path }=191940| ) ) ).
    cl_abap_unit_assert=>assert_equals( act = sales_of( values = grouped pattern = 2 )
                                        exp = VALUE string_table( ( `=266773` ) ) ).
    " each pattern read on its own gives the same groups
    DO lines( patterns ) TIMES.
      DATA(index) = sy-index.
      DATA(single) = NEW zzxxmla1_cl_mdx_facts( cube = reader->cube hierarchies = reader->get_model_hierarchies( )
                                                measures = reader->measures
                    )->cross_values( VALUE #( ( patterns[ index ] ) ) ).
      cl_abap_unit_assert=>assert_equals( act = sales_of( values = grouped pattern = index )
                                          exp = sales_of( values = single pattern = 1 ) ).
    ENDDO.
    " read now, answered by the segments afterwards
    cl_abap_unit_assert=>assert_equals( act = facts->cross_values( patterns ) exp = grouped ).
  ENDMETHOD.

  METHOD slicer_predicate.
    " a compound slicer of two states: the families' sales in both, which their sums in each are
    DATA(california) = state( `CA` ).
    DATA(oregon) = state( `OR` ).
    DATA(drink) = family( `Drink` ).
    DATA(predicate) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_predicate(
      ( kind = zzxxmla1_cl_mdx_facts=>c_predicate-or children = VALUE #( ( 2 ) ( 3 ) ) )
      ( kind = zzxxmla1_cl_mdx_facts=>c_predicate-member member = california[ 1 ] )
      ( kind = zzxxmla1_cl_mdx_facts=>c_predicate-member member = oregon[ 1 ] ) ).
    DATA(values) = facts->cross_values(
      patterns = VALUE #( ( filters = VALUE #( ( hierarchy = drink[ 1 ]-hierarchy level = 1 ) )
                            paths   = VALUE #( ( VALUE #( ( drink[ 1 ]-path ) ) ) ) ) )
      slicer   = predicate ).
    DATA(both) = facts->value( filters = VALUE #( ( drink[ 1 ] ) ( california[ 1 ] ) ) measure = unit_sales )-amount
               + facts->value( filters = VALUE #( ( drink[ 1 ] ) ( oregon[ 1 ] ) ) measure = unit_sales )-amount.
    cl_abap_unit_assert=>assert_equals( act = lines( values ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = values[ 1 ]-amounts[ unit_sales ] exp = both ).
    " the slicer's groups are not kept: without it the family has all its sales
    DATA(plain) = facts->cross_values(
      patterns = VALUE #( ( filters = VALUE #( ( hierarchy = drink[ 1 ]-hierarchy level = 1 ) )
                            paths   = VALUE #( ( VALUE #( ( drink[ 1 ]-path ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = plain[ 1 ]-amounts[ unit_sales ] exp = 24597 ).
  ENDMETHOD.

  METHOD pattern.
    result = VALUE #( filters = VALUE #( ( hierarchy = filter-hierarchy level = filter-level ) )
                      paths   = VALUE #( ( paths ) ) ).
  ENDMETHOD.

  METHOD quarter.
    DATA(member) = reader->lookup_compound( VALUE #( ( name = `Time` quoting = `QUOTED` )
                                                     ( name = `1997` quoting = `QUOTED` )
                                                     ( name = `Q1` quoting = `QUOTED` ) ) )-member.
    result = VALUE #( hierarchy = member-hier_id level = member-key_level path = member-path ).
  ENDMETHOD.

  METHOD roll_up.
    " the families with facts, read for a native set: the All member and two families are their sums, without a read
    DATA(drink) = family( `Drink` ).
    facts->non_empty_paths( VALUE #( ( hierarchy = drink[ 1 ]-hierarchy level = 1 any = abap_true ) ) ).
    DATA(food) = family( `Food` ).
    zzxxmla1_cl_sql=>reset_statistics( ).
    DATA(values) = facts->cross_values( VALUE #( ( )
                                                 ( pattern( filter = drink[ 1 ]
                                                            paths  = VALUE #( ( drink[ 1 ]-path ) ( food[ 1 ]-path ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_sql=>statement_count exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = sales_of( values = values pattern = 1 )
                                        exp = VALUE string_table( ( `=266773` ) ) ).
    " the segment's other families are among them
    cl_abap_unit_assert=>assert_equals( act = sales_of( values = values pattern = 2
                                                        only   = VALUE #( ( drink[ 1 ]-path ) ( food[ 1 ]-path ) ) )
                                        exp = VALUE string_table( ( |{ drink[ 1 ]-path }=24597| )
                                                                  ( |{ food[ 1 ]-path }=191940| ) ) ).
    " a cell of the evaluator too
    cl_abap_unit_assert=>assert_equals( act = facts->value( filters = VALUE #( ) measure = unit_sales )-amount
                                        exp = 266773 ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_sql=>statement_count exp = 0 ).
    " a family's departments are not in the families' groups: read
    DATA(departments) = facts->cross_values( VALUE #( ( pattern(
      filter = VALUE #( hierarchy = drink[ 1 ]-hierarchy level = 2 )
      paths  = VALUE #( ( |{ drink[ 1 ]-path }{ zzxxmla1_cl_model=>c_separator }Beverages| ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_sql=>statement_count exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( departments ) exp = 1 ).
  ENDMETHOD.

  METHOD defaults.
    " the families with facts in any time, read with the first quarter of 1997 as a default member: the same statement
    " gives the families' sales in the quarter, which a reader without it reads
    DATA(drink) = family( `Drink` ).
    DATA(q1) = quarter( ).
    facts->non_empty_paths( filters  = VALUE #( ( hierarchy = drink[ 1 ]-hierarchy level = 1 any = abap_true ) )
                            defaults = VALUE #( ( q1 ) ) ).
    " the pattern of both, its filters in the order of the hierarchies
    DATA(both) = VALUE zzxxmla1_cl_mdx_facts=>ty_cross_pattern(
      filters = VALUE #( ( hierarchy = drink[ 1 ]-hierarchy level = 1 ) ( hierarchy = q1-hierarchy level = q1-level ) )
      paths   = VALUE #( ( VALUE #( ( drink[ 1 ]-path ) ) ) ( VALUE #( ( q1-path ) ) ) ) ).
    IF q1-hierarchy < drink[ 1 ]-hierarchy.
      both = VALUE #( filters = VALUE #( ( both-filters[ 2 ] ) ( both-filters[ 1 ] ) )
                      paths   = VALUE #( ( both-paths[ 2 ] ) ( both-paths[ 1 ] ) ) ).
    ENDIF.
    DATA(patterns) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_cross_pattern(
      ( both ) ( pattern( filter = q1 paths = VALUE #( ( q1-path ) ) ) ) ).
    zzxxmla1_cl_sql=>reset_statistics( ).
    DATA(values) = facts->cross_values( patterns ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_sql=>statement_count exp = 0 ).
    DATA(read) = NEW zzxxmla1_cl_mdx_facts( cube = reader->cube hierarchies = reader->get_model_hierarchies( )
                                            measures = reader->measures )->cross_values( patterns ).
    " Drink in the quarter (the other families' groups of the segment are among them)
    DATA(drink_q1) = VALUE string_table( ( concat_lines_of( table = VALUE string_table( FOR p IN both-paths ( p[ 1 ] ) )
                                                            sep   = `/` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = sales_of( values = values pattern = 1 only = drink_q1 )
                                        exp = sales_of( values = read pattern = 1 only = drink_q1 ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( sales_of( values = read pattern = 1 only = drink_q1 ) ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = sales_of( values = values pattern = 2 )
                                        exp = sales_of( values = read pattern = 2 ) ).
  ENDMETHOD.

  METHOD unconstrained_set.
    " the All member's set has no constraint: it is read on its own, so the families' WHERE stays
    DATA(drink) = family( `Drink` ).
    zzxxmla1_cl_sql=>reset_statistics( ).
    zzxxmla1_cl_sql=>log_statements = abap_true.
    DATA(values) = facts->cross_values( VALUE #( ( pattern( filter = drink[ 1 ] paths = VALUE #( ( drink[ 1 ]-path ) ) ) )
                                                 ( ) ) ).
    zzxxmla1_cl_sql=>log_statements = abap_false.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_sql=>statement_count exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_sql=>statement_log[ 1 ]-rows exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = sales_of( values = values pattern = 1 )
                                        exp = VALUE string_table( ( |{ drink[ 1 ]-path }=24597| ) ) ).
    cl_abap_unit_assert=>assert_equals( act = sales_of( values = values pattern = 2 )
                                        exp = VALUE string_table( ( `=266773` ) ) ).
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

  METHOD ordered_paths.
    DATA(level) = reader->get_level( reader->lookup_compound( VALUE #( ( name = `Product` quoting = `QUOTED` )
                                                                      ( name = `Product Family` quoting = `QUOTED` ) ) )-id ).
    DATA(operands) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_top_operand( ( hierarchy = level-hierarchy
                                                                      level     = level-key_level ) ).
    DATA(filters) = family( `Drink` ).
    DATA(drink) = filters[ 1 ]-path.
    filters = family( `Food` ).
    DATA(food) = filters[ 1 ]-path.
    filters = family( `Non-Consumable` ).
    DATA(non_consumable) = filters[ 1 ]-path.
    " by the key descending, ignoring case: the unassigned family (empty key) last
    cl_abap_unit_assert=>assert_equals(
      act = facts->ordered_paths( operands = operands filters = VALUE #( ) with_empty = abap_true
                                  items = VALUE #( ( operand = 1 level = level-key_level descending = abap_true ) ) )
      exp = VALUE zzxxmla1_cl_mdx_facts=>ty_t_paths( ( VALUE #( ( non_consumable ) ) ) ( VALUE #( ( food ) ) )
                                                     ( VALUE #( ( drink ) ) ) ( VALUE #( ( `` ) ) ) ) ).
    " by unit sales ascending, only the families with facts, the first two
    cl_abap_unit_assert=>assert_equals(
      act = facts->ordered_paths( operands = operands filters = VALUE #( ) with_empty = abap_false limit = 2
                                  items = VALUE #( ( measure = unit_sales ) ) )
      exp = VALUE zzxxmla1_cl_mdx_facts=>ty_t_paths( ( VALUE #( ( drink ) ) ) ( VALUE #( ( non_consumable ) ) ) ) ).
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
