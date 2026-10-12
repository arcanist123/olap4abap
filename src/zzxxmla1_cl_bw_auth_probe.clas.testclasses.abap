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
CLASS ltc_bw_auth_probe DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS c_hierarchy TYPE string
      VALUE `[ZCLDOC                        ZCLDOC_ORG                    001]`.
    "! a text node is its name padded to 32 characters and 0HIER_NODE, a leaf its key
    METHODS node_names FOR TESTING.
    "! lines of 75 characters that give the statement back when joined respecting blanks
    METHODS command_lines FOR TESTING.
ENDCLASS.


CLASS ltc_bw_auth_probe IMPLEMENTATION.

  METHOD node_names.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_probe=>node_name( hierarchy      = c_hierarchy
                                                  characteristic = 'ZCLDOC'
                                                  iobjnm         = '0HIER_NODE'
                                                  nodename       = 'CLINIC' )
      exp = |{ c_hierarchy }.[CLINIC                          0HIER_NODE]| ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_probe=>node_name( hierarchy      = c_hierarchy
                                                  characteristic = 'ZCLDOC'
                                                  iobjnm         = 'ZCLDOC'
                                                  nodename       = '008' )
      exp = |{ c_hierarchy }.[008]| ).
  ENDMETHOD.

  METHOD command_lines.
    TYPES ty_line TYPE c LENGTH 75.
    DATA lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    DATA joined TYPE string.
    DATA(mdx) = |SELECT \{[Measures].[ZCLVISNO]\} ON 0, \{{ c_hierarchy }.[CLINIC                          | &&
                |0HIER_NODE].Children\} ON 1 FROM [$ZCLVISITA]|.
    DATA(result) = zzxxmla1_cl_bw_auth_probe=>command_lines( mdx ).
    LOOP AT result INTO DATA(line).
      cl_abap_unit_assert=>assert_true( xsdbool( strlen( line ) <= 75 ) ).
      APPEND line TO lines.
    ENDLOOP.
    CONCATENATE LINES OF lines INTO joined RESPECTING BLANKS.
    cl_abap_unit_assert=>assert_equals( act = substring( val = joined len = strlen( mdx ) )
                                        exp = mdx ).
    cl_abap_unit_assert=>assert_equals( act = lines( result )
                                        exp = ( strlen( mdx ) + 74 ) DIV 75 ).
  ENDMETHOD.

ENDCLASS.
