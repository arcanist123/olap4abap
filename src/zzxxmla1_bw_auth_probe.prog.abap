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
* Probes BW's analysis authorizations on the clinic demo's authorization-relevant characteristics, the physician ZCLDOC
* and the diagnosis ZCLDIAG (ZZXXMLA1_CL_BW_AUTH_PROBE): runs queries through BW's own MDX engine on the aDSO as the
* current user, once per key date, since the hierarchies of ZCLDOC are version dependent and entirely time dependent
* (docs/clinic-demo.md). Per characteristic flat selections, every hierarchy of the key date and every node of it as
* slicer, on the rows, its children and its parent; combined, the members of the one characteristic with a value or a
* node of the other as slicer. The list shows per query whether BW answered (OK, EMPTY) or refused (NO AUTH, ERROR),
* with BW's message; above it the analysis authorizations that restrict the characteristics and whether the user has
* them. Log on as (or assign the authorization to) the user whose authorization is to be probed.
REPORT zzxxmla1_bw_auth_probe.

DATA key_date TYPE d.
DATA characteristic TYPE rsiobjnm.
DATA hienm TYPE rshienm.
DATA version TYPE rsversion.

SELECTION-SCREEN BEGIN OF BLOCK provider WITH FRAME TITLE t_prov.
PARAMETERS p_cube TYPE c LENGTH 30 DEFAULT '$ZCLVISITA' LOWER CASE.
SELECT-OPTIONS s_char FOR characteristic NO INTERVALS.
PARAMETERS p_meas TYPE c LENGTH 30 DEFAULT 'ZCLVISNO'.
SELECT-OPTIONS s_date FOR key_date NO INTERVALS.
SELECT-OPTIONS s_hienm FOR hienm.
SELECT-OPTIONS s_vers FOR version.
SELECTION-SCREEN END OF BLOCK provider.

SELECTION-SCREEN BEGIN OF BLOCK tests WITH FRAME TITLE t_tests.
PARAMETERS p_flat AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_member AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_slicer AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_rows AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_child AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_parent AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_comb AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_cleaf AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK tests.

INITIALIZATION.
  t_prov = 'Provider, characteristics, key dates, hierarchies'.
  t_tests = 'Queries'.
  s_char[] = VALUE #( sign = 'I' option = 'EQ' ( low = 'ZCLDOC' ) ( low = 'ZCLDIAG' ) ).
  s_date[] = VALUE #( sign = 'I' option = 'EQ' ( low = '20240615' ) ( low = '20250615' ) ).

START-OF-SELECTION.
  DATA(probe) = NEW zzxxmla1_cl_bw_auth_probe(
    cube            = |{ p_cube }|
    characteristics = VALUE #( FOR c IN s_char WHERE ( sign = 'I' ) ( c-low ) )
    measure         = |{ p_meas }| ).
  DATA(authorizations) = probe->authorizations( ).
  DATA(results) = probe->run( key_dates   = VALUE #( FOR date IN s_date WHERE ( sign = 'I' ) ( date-low ) )
                              hierarchies = s_hienm[]
                              versions    = s_vers[]
                              tests       = VALUE #( flat           = p_flat
                                                     members        = p_member
                                                     slicer         = p_slicer
                                                     rows           = p_rows
                                                     children       = p_child
                                                     parent         = p_parent
                                                     combined       = p_comb
                                                     combine_leaves = p_cleaf ) ).
  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = DATA(alv)
                              CHANGING  t_table      = results ).
      alv->get_functions( )->set_all( abap_true ).
      alv->get_columns( )->set_optimize( abap_true ).
      DATA(top) = NEW cl_salv_form_layout_grid( ).
      top->create_label( row = 1 column = 1 text = |User { sy-uname }: analysis authorizations| ).
      LOOP AT authorizations INTO DATA(authorization).
        DATA(row) = sy-tabix + 1.
        top->create_text( row = row column = 1 text = authorization-auth ).
        top->create_text( row = row column = 2 text = COND string( WHEN authorization-assigned = abap_true
                                                                    THEN `assigned` ELSE `not assigned` ) ).
        top->create_text( row = row column = 3 text = authorization-kind ).
        top->create_text( row = row column = 4 text = authorization-details ).
      ENDLOOP.
      alv->set_top_of_list( top ).
      alv->display( ).
    CATCH cx_salv_msg cx_salv_not_found INTO DATA(error).
      MESSAGE error TYPE 'E'.
  ENDTRY.
