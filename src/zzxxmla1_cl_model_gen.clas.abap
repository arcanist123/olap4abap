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
CLASS zzxxmla1_cl_model_gen DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    TYPES:
      BEGIN OF ty_model,
        cube     TYPE zzxxmla1_cube,
        dims     TYPE STANDARD TABLE OF zzxxmla1_dim WITH EMPTY KEY,
        hiers    TYPE STANDARD TABLE OF zzxxmla1_hier WITH EMPTY KEY,
        levels   TYPE STANDARD TABLE OF zzxxmla1_level WITH EMPTY KEY,
        measures TYPE STANDARD TABLE OF zzxxmla1_meas WITH EMPTY KEY,
      END OF ty_model.

    "! Reads the BW metadata of the cube and derives the default model: one dimension per characteristic, a key
    "! hierarchy and one single-level hierarchy per attribute, the SUM key figures as measures. No time handling,
    "! no multi-level hierarchies, no properties.
    METHODS build IMPORTING cube TYPE rsinfocube RETURNING VALUE(model) TYPE ty_model.
    "! Replaces the rows of the cube in the five model tables.
    METHODS save IMPORTING model TYPE ty_model.

  PRIVATE SECTION.
    CONSTANTS c_origin TYPE c LENGTH 1 VALUE 'G'.
    CONSTANTS c_flag   TYPE c LENGTH 1 VALUE 'X'.

    "! BW namespace prefix of an InfoObject: /BI0/ for SAP objects (name starts with 0), /BIC/ for customer ones.
    METHODS namespace IMPORTING iobjnm TYPE rsiobjnm RETURNING VALUE(result) TYPE string.
    "! Name without the leading 0 that BW drops in table and column names of SAP objects.
    METHODS bare_name IMPORTING iobjnm TYPE rsiobjnm RETURNING VALUE(result) TYPE string.
    "! Column name of an InfoObject in its master data table or in the fact table, e.g. /BIC/ZFMSTORE.
    METHODS column_name IMPORTING iobjnm TYPE rsiobjnm RETURNING VALUE(result) TYPE string.
    "! Table of a characteristic: kind S (SIDs) or P (time-independent attributes), e.g. /BIC/PZFMSTORE.
    METHODS table_name IMPORTING kind TYPE c iobjnm TYPE rsiobjnm RETURNING VALUE(result) TYPE string.
    "! The reference data type of a dictionary data type: Numeric for numbers, String for everything else.
    METHODS schema_type IMPORTING datatype TYPE dd03l-datatype RETURNING VALUE(result) TYPE string.
    METHODS column_type IMPORTING table TYPE string column TYPE string RETURNING VALUE(result) TYPE string.
    METHODS text_of IMPORTING iobjnm TYPE rsiobjnm RETURNING VALUE(result) TYPE string.
    METHODS text_of_cube IMPORTING cube TYPE rsinfocube RETURNING VALUE(result) TYPE string.
    METHODS add_hierarchy
      IMPORTING cube        TYPE rsinfocube
                dim_name    TYPE string
                hier_name   TYPE string
                column      TYPE string
                data_type   TYPE string
      CHANGING  model       TYPE ty_model.
    METHODS add_dimension
      IMPORTING cube    TYPE rsinfocube
                iobjnm  TYPE rsiobjnm
      CHANGING  model   TYPE ty_model.
    METHODS add_measures
      IMPORTING cube  TYPE rsinfocube
      CHANGING  model TYPE ty_model.
ENDCLASS.

CLASS zzxxmla1_cl_model_gen IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    DATA(model) = build( 'ZFMSALES' ).
    save( model ).
    out->write( |{ model-cube-cube_name }: { lines( model-dims ) } dimensions, { lines( model-hiers ) } hierarchies, { lines( model-levels ) } levels, { lines( model-measures ) } measures| ).
  ENDMETHOD.

  METHOD build.
    SELECT SINGLE infocube, infoarea FROM rsdcube
      WHERE infocube = @cube AND objvers = 'A'
      INTO @DATA(found).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " the catalog of a cube is its InfoArea: cubes are grouped the way BW groups them
    model-cube = VALUE #( cube_name    = cube
                          catalog_name = found-infoarea
                          caption      = text_of_cube( cube )
                          fact_table   = |{ namespace( cube ) }F{ cube }|
                          origin       = c_origin ).
    GET TIME STAMP FIELD model-cube-generated_at.

    " characteristics of the cube; the package dimension and other technical or time objects are not characteristics
    SELECT d~iobjnm FROM rsddimeiobj AS d
      INNER JOIN rsdiobj AS o ON o~iobjnm = d~iobjnm AND o~objvers = 'A'
      WHERE d~infocube = @cube AND d~objvers = 'A' AND o~iobjtp = 'CHA'
      ORDER BY d~dimension ASCENDING, d~posit ASCENDING
      INTO TABLE @DATA(characteristics).
    LOOP AT characteristics INTO DATA(characteristic).
      add_dimension( EXPORTING cube = cube iobjnm = characteristic-iobjnm CHANGING model = model ).
    ENDLOOP.

    add_measures( EXPORTING cube = cube CHANGING model = model ).
  ENDMETHOD.

  METHOD save.
    DATA(cube_name) = model-cube-cube_name.
    DELETE FROM zzxxmla1_cube  WHERE cube_name = @cube_name.
    DELETE FROM zzxxmla1_dim   WHERE cube_name = @cube_name.
    DELETE FROM zzxxmla1_hier  WHERE cube_name = @cube_name.
    DELETE FROM zzxxmla1_level WHERE cube_name = @cube_name.
    DELETE FROM zzxxmla1_meas  WHERE cube_name = @cube_name.
    INSERT zzxxmla1_cube FROM @model-cube.
    INSERT zzxxmla1_dim   FROM TABLE @model-dims.
    INSERT zzxxmla1_hier  FROM TABLE @model-hiers.
    INSERT zzxxmla1_level FROM TABLE @model-levels.
    INSERT zzxxmla1_meas  FROM TABLE @model-measures.
    COMMIT WORK.
  ENDMETHOD.

  METHOD namespace.
    result = COND #( WHEN iobjnm(1) = '0' THEN `/BI0/` ELSE `/BIC/` ).
  ENDMETHOD.

  METHOD bare_name.
    result = COND #( WHEN iobjnm(1) = '0' THEN substring( val = iobjnm off = 1 ) ELSE CONV string( iobjnm ) ).
  ENDMETHOD.

  METHOD column_name.
    result = |{ namespace( iobjnm ) }{ bare_name( iobjnm ) }|.
  ENDMETHOD.

  METHOD table_name.
    result = |{ namespace( iobjnm ) }{ kind }{ bare_name( iobjnm ) }|.
  ENDMETHOD.

  METHOD schema_type.
    result = SWITCH #( datatype
                       WHEN 'NUMC' OR 'INT1' OR 'INT2' OR 'INT4' OR 'INT8' OR 'DEC' OR 'FLTP' OR 'CURR' OR 'QUAN'
                       THEN `Numeric`
                       ELSE `String` ).
  ENDMETHOD.

  METHOD column_type.
    SELECT SINGLE datatype FROM dd03l
      WHERE tabname = @table AND fieldname = @column AND as4local = 'A'
      INTO @DATA(datatype).
    result = schema_type( datatype ).
  ENDMETHOD.

  METHOD text_of.
    SELECT SINGLE txtlg FROM rsdiobjt
      WHERE iobjnm = @iobjnm AND objvers = 'A' AND langu = @sy-langu
      INTO @result.
    IF sy-subrc <> 0 OR result IS INITIAL.
      SELECT txtlg FROM rsdiobjt
        WHERE iobjnm = @iobjnm AND objvers = 'A'
        ORDER BY langu ASCENDING
        INTO @result UP TO 1 ROWS.
      ENDSELECT.
    ENDIF.
    IF result IS INITIAL.
      result = iobjnm.
    ENDIF.
  ENDMETHOD.

  METHOD text_of_cube.
    SELECT SINGLE txtlg FROM rsdcubet
      WHERE infocube = @cube AND objvers = 'A' AND langu = @sy-langu
      INTO @result.
    IF sy-subrc <> 0 OR result IS INITIAL.
      result = cube.
    ENDIF.
  ENDMETHOD.

  METHOD add_dimension.
    DATA(dim_name) = text_of( iobjnm ).
    DATA(attr_table) = table_name( kind = 'P' iobjnm = iobjnm ).
    DATA(key_column) = column_name( iobjnm ).

    APPEND VALUE #( cube_name      = cube
                    dim_name       = dim_name
                    seq_no         = lines( model-dims ) + 1
                    caption        = dim_name
                    characteristic = iobjnm
                    fk_column      = |SID_{ iobjnm }|
                    sid_table      = table_name( kind = 'S' iobjnm = iobjnm )
                    attr_table     = attr_table
                    key_column     = key_column
                    dim_type       = 'Standard'
                    origin         = c_origin ) TO model-dims.

    " the key hierarchy is the dimension's default hierarchy and carries the dimension's name
    add_hierarchy( EXPORTING cube = cube dim_name = dim_name hier_name = dim_name column = key_column
                             data_type = column_type( table = attr_table column = key_column )
                   CHANGING model = model ).

    " every time-independent attribute becomes a hierarchy of its own
    SELECT attrinm FROM rsdbchatr
      WHERE chabasnm = @iobjnm AND objvers = 'A' AND atrtimfl <> '1'
      ORDER BY posit ASCENDING
      INTO TABLE @DATA(attributes).
    LOOP AT attributes INTO DATA(attribute).
      DATA(column) = column_name( attribute-attrinm ).
      DATA(hier_name) = text_of( attribute-attrinm ).
      IF line_exists( model-hiers[ cube_name = cube dim_name = dim_name hier_name = hier_name ] ).
        hier_name = |{ hier_name } ({ attribute-attrinm })|.
      ENDIF.
      add_hierarchy( EXPORTING cube = cube dim_name = dim_name hier_name = hier_name column = column
                               data_type = column_type( table = attr_table column = column )
                     CHANGING model = model ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_hierarchy.
    APPEND VALUE #( cube_name       = cube
                    dim_name        = dim_name
                    hier_name       = hier_name
                    seq_no          = REDUCE i( INIT n = 1 FOR h IN model-hiers WHERE ( dim_name = dim_name ) NEXT n = n + 1 )
                    caption         = hier_name
                    has_all         = c_flag
                    " The reference: "All " + the hierarchy's name (Dimension.Hierarchy, the key hierarchy has the dimension's) + "s"
                    all_member_name = |All { COND string( WHEN hier_name = dim_name THEN dim_name ELSE |{ dim_name }.{ hier_name }| ) }s|
                    origin          = c_origin ) TO model-hiers.
    APPEND VALUE #( cube_name      = cube
                    dim_name       = dim_name
                    hier_name      = hier_name
                    level_no       = 1
                    level_name     = hier_name
                    caption        = hier_name
                    key_column     = column
                    name_column    = column
                    data_type      = data_type
                    unique_members = c_flag
                    origin         = c_origin ) TO model-levels.
  ENDMETHOD.

  METHOD add_measures.
    " only key figures that are plain sums: SUM as standard and exception aggregation, not non-cumulative
    SELECT c~iobjnm FROM rsdcubeiobj AS c
      INNER JOIN rsdkyf AS k ON k~kyfnm = c~iobjnm AND k~objvers = 'A'
      WHERE c~infocube = @cube AND c~objvers = 'A'
        AND k~aggrgen = 'SUM' AND k~aggrexc = 'SUM' AND k~ncumfl = @space
      ORDER BY c~posit ASCENDING
      INTO TABLE @DATA(key_figures).
    LOOP AT key_figures INTO DATA(key_figure).
      DATA(name) = text_of( key_figure-iobjnm ).
      APPEND VALUE #( cube_name   = cube
                      meas_name   = name
                      seq_no      = lines( model-measures ) + 1
                      caption     = name
                      fact_column = column_name( key_figure-iobjnm )
                      aggregator  = 'sum'
                      visible     = c_flag
                      origin      = c_origin ) TO model-measures.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.