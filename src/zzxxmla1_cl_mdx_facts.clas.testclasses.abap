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
    METHODS non_empty_paths FOR TESTING RAISING zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_facts IMPLEMENTATION.

  METHOD non_empty_paths.
    DATA(reader) = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
    DATA(facts) = NEW zzxxmla1_cl_mdx_facts( cube = reader->cube hierarchies = reader->get_model_hierarchies( )
                                             measures = reader->measures ).
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
