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
CLASS ltc_bw_auth_probe DEFINITION DEFERRED.
CLASS zzxxmla1_cl_bw_auth_probe DEFINITION LOCAL FRIENDS ltc_bw_auth_probe.

CLASS ltc_bw_auth_probe DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS c_hierarchy TYPE string
      VALUE `[ZCLDOC                        ZCLDOC_ORG                    001]`.
    "! a text node is its name padded to 32 characters and 0HIER_NODE, a leaf its key
    METHODS node_names FOR TESTING.
    "! lines of 75 characters that give the statement back when joined respecting blanks
    METHODS command_lines FOR TESTING.
    "! ZCLDIAG_SHR's shapes: a link node and a duplicate leaf asked once, a postable node as leaf and as node
    METHODS node_list FOR TESTING.
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

  METHOD node_list.
    " CARE > CHRONIC > (J45, CARDIO > I10, E11 > E78), FOLLOWUP > REVIEW > (CARDIO link, J45)
    DATA(rows) = VALUE zzxxmla1_cl_bw_auth_probe=>ty_nodes(
      ( nodeid = 1  iobjnm = '0HIER_NODE' nodename = 'CARE'     tlevel = 1 parentid = 0 childid = 2 )
      ( nodeid = 2  iobjnm = '0HIER_NODE' nodename = 'CHRONIC'  tlevel = 2 parentid = 1 childid = 3 )
      ( nodeid = 3  iobjnm = 'ZCLDIAG'    nodename = 'J45'      tlevel = 3 parentid = 2 )
      ( nodeid = 4  iobjnm = '0HIER_NODE' nodename = 'CARDIO'   tlevel = 3 parentid = 2 childid = 5 )
      ( nodeid = 5  iobjnm = 'ZCLDIAG'    nodename = 'I10'      tlevel = 4 parentid = 4 )
      ( nodeid = 6  iobjnm = 'ZCLDIAG'    nodename = 'E11'      tlevel = 3 parentid = 2 childid = 7 )
      ( nodeid = 7  iobjnm = 'ZCLDIAG'    nodename = 'E78'      tlevel = 4 parentid = 6 )
      ( nodeid = 8  iobjnm = '0HIER_NODE' nodename = 'FOLLOWUP' tlevel = 2 parentid = 1 childid = 9 )
      ( nodeid = 9  iobjnm = '0HIER_NODE' nodename = 'REVIEW'   tlevel = 3 parentid = 8 childid = 10 )
      ( nodeid = 10 iobjnm = '0HIER_NODE' nodename = 'CARDIO'   tlevel = 4 parentid = 9 link = 'X' )
      ( nodeid = 11 iobjnm = 'ZCLDIAG'    nodename = 'J45'      tlevel = 4 parentid = 9 ) ).
    DATA(nodes) = zzxxmla1_cl_bw_auth_probe=>node_list( characteristic = 'ZCLDIAG' rows = rows ).
    DATA(asked) = VALUE string_table( FOR n IN nodes ( zzxxmla1_cl_bw_auth_probe=>row_node( characteristic = 'ZCLDIAG'
                                                                                           node           = n ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = asked
      exp = VALUE string_table( ( `CARE` ) ( `CHRONIC` ) ( `J45` ) ( `CARDIO` ) ( `I10` ) ( `E11` ) ( `E11 ZCLDIAG` )
                                ( `E78` ) ( `FOLLOWUP` ) ( `REVIEW` ) ) ).
    " the duplicate leaf is its first occurrence, the shallow one
    cl_abap_unit_assert=>assert_equals( act = nodes[ 3 ]-tlevel exp = 3 ).
    cl_abap_unit_assert=>assert_false( nodes[ 6 ]-postable ).
    cl_abap_unit_assert=>assert_true( nodes[ 7 ]-postable ).
    " the leaf by its key, the postable node padded with the characteristic
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_probe=>node_name( hierarchy      = `[H]`
                                                  characteristic = 'ZCLDIAG'
                                                  iobjnm         = nodes[ 6 ]-iobjnm
                                                  nodename       = nodes[ 6 ]-nodename
                                                  postable       = nodes[ 6 ]-postable )
      exp = `[H].[E11]` ).
    " the InfoObject at its full length (rsiobjnm), as in every recorded statement of a text node
    DATA node32 TYPE c LENGTH 32 VALUE 'E11'.
    DATA iobjnm TYPE rsiobjnm VALUE 'ZCLDIAG'.
    DATA expected TYPE string.
    CONCATENATE `[H].[` node32 iobjnm `]` INTO expected RESPECTING BLANKS.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_probe=>node_name( hierarchy      = `[H]`
                                                  characteristic = 'ZCLDIAG'
                                                  iobjnm         = nodes[ 7 ]-iobjnm
                                                  nodename       = nodes[ 7 ]-nodename
                                                  postable       = nodes[ 7 ]-postable )
      exp = expected ).
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
