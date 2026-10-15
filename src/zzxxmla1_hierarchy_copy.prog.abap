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
* Copies BW hierarchies as the engine reads them (ZZXXMLA1_CL_BW_HIERARCHY_COPY, docs/next-steps.md, Now:
* time-independent BW hierarchies): per characteristic its node table, closure table and not-assigned view are created
* if it has none (in $TMP), then each of its time-independent hierarchies that are not version dependent is copied if
* BW's current version has no copy yet. The list shows per hierarchy the copy or why it was refused, its counts and
* the closure a query reads (the not-assigned view where the hierarchy shows that node, else the closure table).
REPORT zzxxmla1_hierarchy_copy LINE-SIZE 255.

DATA characteristic TYPE rsiobjnm.
DATA hierarchy_name TYPE rshienm.

SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(30) t_iobj FOR FIELD s_iobj.
SELECT-OPTIONS s_iobj FOR characteristic OBLIGATORY.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(30) t_hienm FOR FIELD s_hienm.
SELECT-OPTIONS s_hienm FOR hierarchy_name.
SELECTION-SCREEN END OF LINE.

INITIALIZATION.
  t_iobj = 'Characteristic (basic)'.
  t_hienm = 'Hierarchy (empty: all)'.

START-OF-SELECTION.
  DATA(rows) = NEW zzxxmla1_cl_bw_hierarchy_copy( )->run( characteristics = s_iobj[] hierarchies = s_hienm[] ).
  IF rows IS INITIAL.
    WRITE / 'No time-independent hierarchy that is not version dependent is selected.'.
    RETURN.
  ENDIF.
  FORMAT COLOR COL_HEADING.
  WRITE: / 'Characteristic', 16 'Hierarchy', 48 'Copy of', 60 'Refilled', 70 'Closure read', 88 'Nodes',
           96 'Inner', 104 'Depth', 111 'Closure rows', 125 'Leaves', 134 'All', 142 'Not assigned',
           157 'Time (ms)'.
  FORMAT COLOR OFF.
  ULINE.
  LOOP AT rows INTO DATA(row).
    IF row-error IS NOT INITIAL.
      FORMAT COLOR COL_NEGATIVE.
      WRITE: / row-characteristic, 16 row-name, 48 row-error.
      FORMAT COLOR OFF.
      CONTINUE.
    ENDIF.
    DATA(copy) = |{ row-hierarchy-hiesid }/{ row-hierarchy-sver }|.
    DATA(not_assigned) = COND string( WHEN row-hierarchy-rest_shown = abap_true THEN |{ row-rest_values }|
                                      ELSE `suppressed` ).
    DATA(milliseconds) = row-microseconds DIV 1000.
    WRITE: / row-characteristic, 16 row-name, 48 copy, 60 row-hierarchy-refilled, 70 row-hierarchy-closure,
             88(7) row-nodes, 96(7) row-inner_nodes, 104(6) row-depth, 111(12) row-closure_rows,
             125(8) row-identity_rows, 134(7) row-all_values, 142 not_assigned, 157(9) milliseconds.
  ENDLOOP.
  ULINE.
  WRITE: / 'Closure rows: the inner nodes'' rows and one identity row per leaf; All: the values of the All member',
         / 'as a query reads them (with the not-assigned values where the hierarchy shows that node).'.
