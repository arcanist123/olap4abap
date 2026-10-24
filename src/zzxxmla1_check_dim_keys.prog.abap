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
* Checks that the key of every dimension of a schema is unique in the dimension's table (ZZXXMLA1_CL_DIM_KEY_CHECK):
* a key with several rows multiplies the facts it joins. The schema is a file of the server (p_file, e.g.
* /WEB-INF/schema/FoodmartBW.xml) or, without one, every catalog of datasources.xml. The list shows per cube and
* dimension the table, its rows, distinct keys, NULL keys, the rows beyond one per key and the most frequent
* duplicated keys.
REPORT zzxxmla1_check_dim_keys.

SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(35) t_file FOR FIELD p_file.
PARAMETERS p_file TYPE c LENGTH 200 LOWER CASE VISIBLE LENGTH 60.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_errors AS CHECKBOX.
SELECTION-SCREEN COMMENT 4(70) t_errors FOR FIELD p_errors.
SELECTION-SCREEN END OF LINE.

INITIALIZATION.
  t_file = 'Schema file (empty: all catalogs)'.
  t_errors = 'Only dimensions with problems'.

START-OF-SELECTION.
  DATA results TYPE zzxxmla1_cl_dim_key_check=>ty_t_result.
  TRY.
      DATA(check) = NEW zzxxmla1_cl_dim_key_check( ).
      IF p_file IS INITIAL.
        results = check->check_catalogs( ).
      ELSE.
        results = check->check_file( condense( p_file ) ).
      ENDIF.
    CATCH zzxxmla1_cx_xmla INTO DATA(fault).
      MESSAGE fault->description TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.
  IF p_errors = abap_true.
    DELETE results WHERE status = zzxxmla1_cl_dim_key_check=>c_status-ok.
  ENDIF.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = DATA(alv)
                              CHANGING  t_table      = results ).
      alv->get_functions( )->set_all( abap_true ).
      alv->get_columns( )->set_optimize( abap_true ).
      alv->get_display_settings( )->set_list_header(
        |Dimension keys: { lines( results ) } dimensions, | &&
        |{ REDUCE i( INIT n = 0 FOR r IN results WHERE ( status <> zzxxmla1_cl_dim_key_check=>c_status-ok )
                     NEXT n = n + 1 ) } with problems| ).
      alv->display( ).
    CATCH cx_salv_msg INTO DATA(error).
      MESSAGE error TYPE 'E'.
  ENDTRY.
