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
"! BW's own answers on the clinic demo's hierarchies (sapcli class execute): per hierarchy every member with its
"! unique name, level, number of children, caption, short, medium and long text (BW's properties 1, 5 and 4 followed by
"! the characteristic: [1ZCLSERV], [5ZCLSERV], [4ZCLSERV]) and the values of the measures, read through BW's MDX engine
"! (BAPI_MDDATASET_*) with the members of the hierarchy on the rows; first the provider's total. These are the expected
"! answers for olap4abap's BW hierarchies (docs/next-steps.md, time-independent BW hierarchies): BW counts a value
"! reached by several paths once per node. Output: a line per member, fields separated by tabs (hierarchy, ordinal,
"! level, children, unique name, caption, the three texts, the measures); scripts/bw_hierarchy_capture.py keeps it as JSON.
"! BW's MDX shows per name and version of a time-dependent hierarchy (the physician's ZCLDOC_ORG and ZCLDOC_SITE) the
"! slice valid at the key date: the probe sets it to 9999-12-31, the slice olap4abap serves
"! (ZZXXMLA1_CL_BW_HIERARCHY_COPY=>c_valid_to).
CLASS zzxxmla1_cl_bw_hierarchy_probe DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    TYPES: BEGIN OF ty_member,
             hierarchy TYPE string,
             ordinal   TYPE i,
             level     TYPE i,
             children  TYPE i,
             unique    TYPE string,
             caption   TYPE string,
             "! short, medium and long text
             texts     TYPE string_table,
             values    TYPE string_table,
           END OF ty_member.
    TYPES ty_members TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.

    METHODS constructor
      IMPORTING cube     TYPE string DEFAULT `$ZCLVISITA`
                measures TYPE string_table OPTIONAL.

    "! the members of every hierarchy of the characteristic BW's MDX shows, with BW's values; an error is a member
    "! with the message as caption
    METHODS members
      IMPORTING characteristic TYPE string
      RETURNING VALUE(result)  TYPE ty_members.

    "! the provider's total of each measure
    METHODS total
      RETURNING VALUE(result) TYPE ty_members.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA cube TYPE string.
    DATA measures TYPE string_table.

    METHODS hierarchies
      IMPORTING characteristic TYPE string
      RETURNING VALUE(result)  TYPE string_table.
    "! runs a statement, its rows (axis 1, if any) with their values and, with a characteristic, its texts
    METHODS execute
      IMPORTING hierarchy      TYPE string
                rows           TYPE string OPTIONAL
                characteristic TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE ty_members.
ENDCLASS.



CLASS zzxxmla1_cl_bw_hierarchy_probe IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    CALL FUNCTION 'RRT_SET_KEY_DATE'
      EXPORTING
        i_key_date = zzxxmla1_cl_bw_hierarchy_copy=>c_valid_to
        i_explicit = abap_true
      EXCEPTIONS
        x_message  = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      out->write( |TOTAL\t0\t0\t0\t\tERROR RRT_SET_KEY_DATE failed ({ sy-subrc })\t\t\t| ).
      RETURN.
    ENDIF.
    DATA(members) = total( ).
    LOOP AT VALUE string_table( ( `ZCLDIAG` ) ( `ZCLPAT` ) ( `ZCLSERV` ) ( `ZCLDOC` ) ) INTO DATA(characteristic).
      APPEND LINES OF members( characteristic ) TO members.
    ENDLOOP.
    LOOP AT members INTO DATA(member).
      " three text fields on every line, the total's empty
      WHILE lines( member-texts ) < 3.
        APPEND `` TO member-texts.
      ENDWHILE.
      out->write( |{ member-hierarchy }\t{ member-ordinal }\t{ member-level }\t{ member-children }\t{
                  member-unique }\t{ member-caption }\t{ concat_lines_of( table = member-texts sep = |\t| ) }\t{
                  concat_lines_of( table = member-values sep = |\t| ) }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD constructor.
    me->cube = cube.
    me->measures = measures.
    IF me->measures IS INITIAL.
      me->measures = VALUE #( ( `ZCLVISNO` ) ( `ZCLCHRG` ) ).
    ENDIF.
  ENDMETHOD.

  METHOD members.
    LOOP AT hierarchies( characteristic ) INTO DATA(hierarchy).
      APPEND LINES OF execute( hierarchy      = hierarchy
                               rows           = |\{{ hierarchy }.Members\}|
                               characteristic = characteristic ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD total.
    result = execute( `TOTAL` ).
  ENDMETHOD.

  METHOD hierarchies.
    DATA list TYPE STANDARD TABLE OF bapi6110hry.
    DATA return TYPE bapiret2.
    DATA cat_nam TYPE bapi6110hry-cat_nam VALUE '$INFOCUBE'.
    DATA cube_nam TYPE bapi6110hry-cube_nam.
    DATA dim_unam TYPE bapi6110hry-dim_unam.
    cube_nam = |[{ cube }]|.
    dim_unam = |[{ characteristic }]|.
    CALL FUNCTION 'BAPI_MDPROVIDER_GET_HIERARCHYS'
      EXPORTING
        cat_nam     = cat_nam
        cube_nam    = cube_nam
        dim_unam    = dim_unam
      IMPORTING
        return      = return
      TABLES
        hierarchies = list.
    " the characteristic's own (flat) hierarchy is named as the characteristic
    LOOP AT list INTO DATA(entry) WHERE hry_nam <> characteristic.
      APPEND |{ entry-hry_unam }| TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD execute.
    DATA lines TYPE STANDARD TABLE OF bapi6111mdx.
    DATA datasetid TYPE bapi6111gen-obj_handle.
    DATA return TYPE bapiret2.
    DATA tuples TYPE STANDARD TABLE OF bapi6111mpp.
    DATA header TYPE STANDARD TABLE OF bapi6111fsd.
    DATA data TYPE STANDARD TABLE OF bapi6111fsd.
    DATA axis TYPE bapi6111axi-axis VALUE 1.
    DATA property_keys TYPE STANDARD TABLE OF bapi6111opk.
    DATA property_values TYPE STANDARD TABLE OF bapi6111opv.
    " short, medium and long text
    DATA(properties) = VALUE string_table( ( |1{ characteristic }| ) ( |5{ characteristic }| )
                                           ( |4{ characteristic }| ) ).

    DATA(mdx) = |SELECT \{{ concat_lines_of( table = VALUE string_table( FOR m IN measures
                                                                         ( |[Measures].[{ m }]| ) ) sep = `, ` ) }\} ON 0|.
    IF rows IS NOT INITIAL.
      IF characteristic IS NOT INITIAL.
        DATA(names) = VALUE string_table( FOR p IN properties ( |[{ characteristic }].[{ p }]| ) ).
        mdx = |{ mdx }, { rows } DIMENSION PROPERTIES { concat_lines_of( table = names sep = `, ` ) } ON 1|.
      ELSE.
        mdx = |{ mdx }, { rows } ON 1|.
      ENDIF.
    ENDIF.
    mdx = |{ mdx } FROM [{ cube }]|.
    " lines of 75 characters, which BW joins respecting blanks (ZZXXMLA1_CL_BW_AUTH_PROBE=>command_lines)
    LOOP AT zzxxmla1_cl_bw_auth_probe=>command_lines( mdx ) INTO DATA(line).
      APPEND VALUE #( line = line ) TO lines.
    ENDLOOP.

    CALL FUNCTION 'BAPI_MDDATASET_CREATE_OBJECT'
      IMPORTING
        return       = return
        datasetid    = datasetid
      TABLES
        command_text = lines.
    IF return-type NA 'EAX'.
      CALL FUNCTION 'BAPI_MDDATASET_SELECT_DATA'
        EXPORTING
          datasetid = datasetid
        IMPORTING
          return    = return.
    ENDIF.
    IF return-type NA 'EAX' AND rows IS NOT INITIAL.
      CALL FUNCTION 'BAPI_MDDATASET_GET_AXIS_DATA'
        EXPORTING
          datasetid     = datasetid
          axis          = axis
        IMPORTING
          return        = return
        TABLES
          mndtry_prptys      = tuples
          option_prptys_keys = property_keys
          option_prptys_vals = property_values.
    ENDIF.
    IF return-type NA 'EAX'.
      CALL FUNCTION 'BAPI_MDDATASET_GET_FLAT_DATA'
        EXPORTING
          datasetid = datasetid
        IMPORTING
          return    = return
        TABLES
          header    = header
          data      = data.
    ENDIF.
    IF return-type CA 'EAX'.
      result = VALUE #( ( hierarchy = hierarchy caption = |ERROR { return-id } { return-number }: {
                                                            return-message }| ) ).
    ELSE.
      " a member per tuple; the values are the last columns of its row of the flat data, in the order of the rows
      DATA(count) = lines( measures ).
      DATA(columns) = 0.
      LOOP AT data INTO DATA(cell).
        columns = nmax( val1 = columns val2 = CONV i( cell-column ) + 1 ).
      ENDLOOP.
      DATA(ordinal) = 0.
      DATA row_values TYPE string_table.
      DATA(last_row) = -1.
      LOOP AT data INTO cell.
        IF CONV i( cell-row ) <> last_row.
          IF last_row >= 0.
            APPEND VALUE #( hierarchy = hierarchy ordinal = ordinal values = row_values ) TO result.
            ordinal = ordinal + 1.
          ENDIF.
          CLEAR row_values.
          last_row = cell-row.
        ENDIF.
        IF CONV i( cell-column ) >= columns - count.
          APPEND condense( |{ cell-data }| ) TO row_values.
        ENDIF.
      ENDLOOP.
      IF last_row >= 0.
        APPEND VALUE #( hierarchy = hierarchy ordinal = ordinal values = row_values ) TO result.
      ENDIF.
      LOOP AT result ASSIGNING FIELD-SYMBOL(<member>).
        READ TABLE tuples INTO DATA(tuple) WITH KEY tuple_ordinal = <member>-ordinal.
        IF sy-subrc = 0.
          <member>-level = tuple-lvl_number.
          <member>-children = tuple-children.
          <member>-unique = tuple-mem_unam.
          <member>-caption = tuple-mem_cap.
        ENDIF.
        IF characteristic IS NOT INITIAL.
          LOOP AT properties INTO DATA(property).
            DATA(text) = ``.
            LOOP AT property_keys INTO DATA(property_key) WHERE prpty_nam CS |[{ property }]|.
              text = VALUE #( property_values[ tuple_ordinal = <member>-ordinal
                                               prpty_key     = property_key-prpty_key ]-prpty_val OPTIONAL ).
            ENDLOOP.
            APPEND text TO <member>-texts.
          ENDLOOP.
        ENDIF.
      ENDLOOP.
      IF lines( tuples ) <> lines( result ) AND rows IS NOT INITIAL.
        APPEND VALUE #( hierarchy = hierarchy caption = |ERROR { lines( tuples ) } tuples, {
                                                        lines( result ) } rows| ) TO result.
      ENDIF.
    ENDIF.

    CALL FUNCTION 'BAPI_MDDATASET_DELETE_OBJECT'
      EXPORTING
        datasetid = datasetid
      IMPORTING
        return    = return.
  ENDMETHOD.

ENDCLASS.
