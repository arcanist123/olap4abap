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
"! The BW analysis authorizations of a user on a provider at a key date, as a region, and the check of a query's
"! selection against it (docs/next-steps.md, Now: analysis authorisations, step 3; the rules in docs/mvp-scope.md,
"! Authorisation decision, BW's rules).
"! The region is an OR over the user's authorizations that apply to the provider of an AND over its
"! authorization-relevant characteristics: per authorization a sub-cube that allows per characteristic all values
"! (CP *), the aggregate (:), flat values (EQ, BT, CP; # the not-assigned value) and per hierarchy line the nodes it
"! shows and the leaves below them. An authorization applies when its special characteristics admit the provider
"! (0TCAIPROV), display (0TCAACTVT 03) and today (0TCAVALID), each as far as it is authorization relevant, and it has
"! a line for every authorization-relevant characteristic of the provider. A hierarchy line applies to the hierarchy of
"! its name and version, in the slice valid at the key date whatever the line's date, by node type: 0 the node only, 1
"! its subtree, 2 its subtree down to an absolute level, 3 the complete hierarchy (4, a relative level, BW corrects to
"! 3 without a node variable). An applying authorization with a variable ($) makes the user not authorized: olap4abap
"! fills no variables.
"! read( ) reads it from BW (RSECVAL_STRING, RSECHIE_STRING, the user's S_RS_AUTH and RSECUSERAUTH, RSHIEDIR and the
"! hierarchy tables); create( ) builds it from given lines, for the unit tests.
CLASS zzxxmla1_cl_bw_auth DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES ty_characteristics TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.
    TYPES ty_auths TYPE STANDARD TABLE OF rsauth WITH EMPTY KEY.
    "! a value line of an analysis authorization (RSECVAL_STRING); low : is the aggregate, # the not-assigned value
    TYPES: BEGIN OF ty_value_line,
             auth   TYPE rsauth,
             iobjnm TYPE rsiobjnm,
             sign   TYPE c LENGTH 1,
             option TYPE c LENGTH 2,
             low    TYPE string,
             high   TYPE string,
           END OF ty_value_line.
    TYPES ty_value_lines TYPE STANDARD TABLE OF ty_value_line WITH EMPTY KEY.
    "! a hierarchy line (RSECHIE_STRING): a node by name and InfoObject (0HIER_NODE for a text node) of the hierarchy
    "! of the name and version, its node type (0 to 4), level (type 2) and date (TCTHIEDATE, the slice its values come
    "! from)
    TYPES: BEGIN OF ty_hierarchy_line,
             auth        TYPE rsauth,
             iobjnm      TYPE rsiobjnm,
             hienm       TYPE rshienm,
             version     TYPE rsversion,
             node_iobjnm TYPE rsiobjnm,
             node        TYPE string,
             type        TYPE c LENGTH 1,
             level       TYPE i,
             date        TYPE d,
           END OF ty_hierarchy_line.
    TYPES ty_hierarchy_lines TYPE STANDARD TABLE OF ty_hierarchy_line WITH EMPTY KEY.
    "! a node of a hierarchy slice (/BIC/H of the characteristic): a leaf has the characteristic as InfoObject, an
    "! interval (/BIC/J) its values low to high, a link node the children of the node of its name that is no link
    TYPES: BEGIN OF ty_node,
             nodeid   TYPE i,
             parentid TYPE i,
             iobjnm   TYPE rsiobjnm,
             name     TYPE string,
             level    TYPE i,
             link     TYPE abap_bool,
             interval TYPE abap_bool,
             low      TYPE string,
             high     TYPE string,
           END OF ty_node.
    TYPES ty_nodes TYPE STANDARD TABLE OF ty_node WITH EMPTY KEY.
    "! the slice of a hierarchy (name and version) valid at a date; no nodes if it has none then
    TYPES: BEGIN OF ty_slice,
             iobjnm  TYPE rsiobjnm,
             hienm   TYPE rshienm,
             version TYPE rsversion,
             date    TYPE d,
             nodes   TYPE ty_nodes,
           END OF ty_slice.
    TYPES ty_slices TYPE STANDARD TABLE OF ty_slice WITH EMPTY KEY.
    "! what the region is made of: the provider's authorization-relevant characteristics, the special ones that are
    "! authorization relevant, the user's authorizations with their lines and the slices their hierarchy lines name: at
    "! the key date (the nodes the user sees) and at each line's date (value_slices: the values a line authorizes, as
    "! BW takes them whatever the key date; the key date's slice where there is none)
    TYPES: BEGIN OF ty_lines,
             provider        TYPE string,
             today           TYPE d,
             characteristics TYPE ty_characteristics,
             specials        TYPE ty_characteristics,
             auths           TYPE ty_auths,
             values          TYPE ty_value_lines,
             hierarchies     TYPE ty_hierarchy_lines,
             slices          TYPE ty_slices,
             value_slices    TYPE ty_slices,
           END OF ty_lines.
    "! a node of a hierarchy the user may see: whether it may be expanded (its children are shown), whether it is a top
    "! node (its parent is not shown: the user's hierarchy is re-rooted there), its parent in the hierarchy
    TYPES: BEGIN OF ty_visible_node,
             iobjnm        TYPE rsiobjnm,
             name          TYPE string,
             level         TYPE i,
             expandable    TYPE abap_bool,
             top           TYPE abap_bool,
             parent_iobjnm TYPE rsiobjnm,
             parent_name   TYPE string,
           END OF ty_visible_node.
    TYPES ty_visible_nodes TYPE SORTED TABLE OF ty_visible_node WITH UNIQUE KEY iobjnm name.
    "! what the user may see of a hierarchy: all of it, or the nodes (none: the hierarchy is refused); lines: the user
    "! has a line on the hierarchy (BW lists it to the user), also if the slice has none of its nodes; complete: a line
    "! of type 3 shows the complete hierarchy, its node of the values not assigned (REST_H) too
    TYPES: BEGIN OF ty_access,
             all      TYPE abap_bool,
             lines    TYPE abap_bool,
             complete TYPE abap_bool,
             nodes    TYPE ty_visible_nodes,
           END OF ty_access.
    "! the member of a characteristic in a tuple of a query's selection: a value (its key, '' or # the not-assigned
    "! one), a node of a hierarchy (a leaf is a node whose InfoObject is the characteristic) or the aggregate (the All
    "! member, or the characteristic not in the tuple); named: the query names it (an identifier, not a set function)
    TYPES: BEGIN OF ty_member,
             iobjnm      TYPE rsiobjnm,
             kind        TYPE c LENGTH 1,
             value       TYPE string,
             hienm       TYPE rshienm,
             version     TYPE rsversion,
             node_iobjnm TYPE rsiobjnm,
             named       TYPE abap_bool,
           END OF ty_member.
    TYPES ty_tuple TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.
    TYPES ty_selection TYPE STANDARD TABLE OF ty_tuple WITH EMPTY KEY.
    "! the answer of the check: allowed, or refused (no authorization, or a value the user may not see at all, which
    "! BW does not know) with BW's message
    TYPES: BEGIN OF ty_check,
             status  TYPE c LENGTH 8,
             reason  TYPE c LENGTH 12,
             message TYPE string,
           END OF ty_check.

    CONSTANTS: BEGIN OF c_kind,
                 value     TYPE c LENGTH 1 VALUE 'V',
                 node      TYPE c LENGTH 1 VALUE 'N',
                 aggregate TYPE c LENGTH 1 VALUE 'A',
               END OF c_kind.
    CONSTANTS: BEGIN OF c_status,
                 allowed TYPE c LENGTH 8 VALUE 'ALLOWED',
                 no_auth TYPE c LENGTH 8 VALUE 'NO AUTH',
                 unknown TYPE c LENGTH 8 VALUE 'UNKNOWN',
               END OF c_status.
    "! why a selection is refused
    CONSTANTS: BEGIN OF c_reason,
                 provider    TYPE c LENGTH 12 VALUE 'PROVIDER',     " no authorization applies to the provider
                 variable    TYPE c LENGTH 12 VALUE 'VARIABLE',     " an applying authorization has a variable
                 no_values   TYPE c LENGTH 12 VALUE 'NO VALUES',    " the characteristic has no value for the user
                 value       TYPE c LENGTH 12 VALUE 'VALUE',        " a value named outside every authorization
                 hierarchy   TYPE c LENGTH 12 VALUE 'HIERARCHY',    " a hierarchy without a line of the user
                 node        TYPE c LENGTH 12 VALUE 'NODE',         " a node the lines on its hierarchy do not show
                 combination TYPE c LENGTH 12 VALUE 'COMBINATION',  " a tuple outside every sub-cube
               END OF c_reason.
    CONSTANTS c_text_node TYPE rsiobjnm VALUE '0HIER_NODE'.
    CONSTANTS c_key_date TYPE d VALUE '99991231'.

    "! The region of the user on the provider (an InfoCube or aDSO) at the key date.
    "! @parameter user | the user BW checks: RSEC_GET_USERNAME (current_user) for the caller's
    CLASS-METHODS read
      IMPORTING !user         TYPE xubname
                provider      TYPE csequence
                key_date      TYPE d DEFAULT c_key_date
                today         TYPE d DEFAULT sy-datum
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_bw_auth
      RAISING   zzxxmla1_cx_bw_provider.
    "! The region of given lines.
    CLASS-METHODS create
      IMPORTING !lines        TYPE ty_lines
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_bw_auth.
    "! The user whose analysis authorizations BW checks: sy-uname, or the one of BW's "Execute as Other User".
    CLASS-METHODS current_user
      RETURNING VALUE(result) TYPE xubname.
    "! The slice of the hierarchy valid at the key date, from RSHIEDIR and the hierarchy tables; no nodes if there is
    "! none.
    CLASS-METHODS read_slice
      IMPORTING iobjnm        TYPE rsiobjnm
                hienm         TYPE rshienm
                version       TYPE rsversion
                key_date      TYPE d
      RETURNING VALUE(result) TYPE ty_slice.

    "! Whether the query's selection is in the region: first the members the query names (a value outside every
    "! authorization is unknown, a hierarchy or node outside the lines refused), then every member, then each tuple
    "! in one sub-cube (a characteristic not in the tuple is aggregated, which needs :).
    METHODS check
      IMPORTING selection     TYPE ty_selection
      RETURNING VALUE(result) TYPE ty_check.
    "! The check of members without their tuples, for a query that shows no tuple (the children of a node that may
    "! not be expanded): the provider, then the members the query names, then the others.
    METHODS check_members
      IMPORTING members       TYPE ty_tuple
      RETURNING VALUE(result) TYPE ty_check.
    "! Whether one sub-cube allows everything (0BI_ALL, CP * on every characteristic): no check is needed.
    METHODS unrestricted
      RETURNING VALUE(result) TYPE abap_bool.
    "! What the user may see of a hierarchy of a characteristic, over all sub-cubes.
    METHODS hierarchy_access
      IMPORTING iobjnm        TYPE rsiobjnm
                hienm         TYPE rshienm
                version       TYPE rsversion
      RETURNING VALUE(result) TYPE ty_access.
    "! The authorizations that apply to the provider.
    METHODS applying
      RETURNING VALUE(result) TYPE ty_auths.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_range,
             sign   TYPE c LENGTH 1,
             option TYPE c LENGTH 2,
             low    TYPE string,
             high   TYPE string,
           END OF ty_range.
    TYPES ty_ranges TYPE STANDARD TABLE OF ty_range WITH EMPTY KEY.
    "! the nodes one authorization shows of a hierarchy
    TYPES: BEGIN OF ty_hierarchy_part,
             hienm   TYPE rshienm,
             version  TYPE rsversion,
             complete TYPE abap_bool,
             nodes    TYPE ty_visible_nodes,
           END OF ty_hierarchy_part.
    TYPES ty_hierarchy_parts TYPE SORTED TABLE OF ty_hierarchy_part WITH UNIQUE KEY hienm version.
    "! what one authorization allows of one characteristic
    TYPES: BEGIN OF ty_part,
             iobjnm      TYPE rsiobjnm,
             all         TYPE abap_bool,
             aggregate   TYPE abap_bool,
             ranges      TYPE ty_ranges,
             hierarchies TYPE ty_hierarchy_parts,
           END OF ty_part.
    TYPES ty_parts TYPE SORTED TABLE OF ty_part WITH UNIQUE KEY iobjnm.
    TYPES: BEGIN OF ty_subcube,
             auth  TYPE rsauth,
             parts TYPE ty_parts,
           END OF ty_subcube.
    TYPES ty_subcubes TYPE STANDARD TABLE OF ty_subcube WITH EMPTY KEY.
    "! what a hierarchy line covers: the nodes it shows and the values of the leaves and intervals among them
    TYPES: BEGIN OF ty_cover,
             nodes  TYPE ty_visible_nodes,
             ranges TYPE ty_ranges,
           END OF ty_cover.

    CONSTANTS c_display TYPE string VALUE `03`.
    CONSTANTS: BEGIN OF c_special,
                 provider TYPE rsiobjnm VALUE '0TCAIPROV',
                 activity TYPE rsiobjnm VALUE '0TCAACTVT',
                 validity TYPE rsiobjnm VALUE '0TCAVALID',
               END OF c_special.

    DATA provider TYPE string.
    DATA characteristics TYPE ty_characteristics.
    DATA subcubes TYPE ty_subcubes.
    DATA variable TYPE abap_bool.

    "! the part of one characteristic in an authorization; not present: the authorization has no line for it
    CLASS-METHODS part
      IMPORTING iobjnm        TYPE rsiobjnm
                !values       TYPE ty_value_lines
                hierarchies   TYPE ty_hierarchy_lines
                slices        TYPE ty_slices
                value_slices  TYPE ty_slices
      EXPORTING present       TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_part.
    "! the nodes a hierarchy line shows in the slice and the values below them
    CLASS-METHODS cover
      IMPORTING !line         TYPE ty_hierarchy_line
                slice         TYPE ty_slice
      RETURNING VALUE(result) TYPE ty_cover.
    "! whether the value is in the ranges: in an including one and in no excluding one
    CLASS-METHODS in_ranges
      IMPORTING !value        TYPE csequence
                ranges        TYPE ty_ranges
      RETURNING VALUE(result) TYPE abap_bool.
    "! whether the value is in one range (EQ, BT, CP with * and +)
    CLASS-METHODS in_range
      IMPORTING !value        TYPE csequence
                !range        TYPE ty_range
      RETURNING VALUE(result) TYPE abap_bool.
    "! whether the value matches BW's pattern: * any characters, + one, case matters; a value of digits (NUMC) also
    "! matches with the pattern's leading digits as a number of its length, as BW does (01* admits 001 and 010)
    CLASS-METHODS pattern_matches
      IMPORTING !value        TYPE csequence
                pattern       TYPE csequence
      RETURNING VALUE(result) TYPE abap_bool.
    "! the not-assigned value as '' (# in BW's authorizations and captions)
    CLASS-METHODS normalized
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! whether a line is a variable ($)
    CLASS-METHODS is_variable
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE abap_bool.

    "! whether the part allows the member
    CLASS-METHODS admits
      IMPORTING part          TYPE ty_part
                member        TYPE ty_member
      RETURNING VALUE(result) TYPE abap_bool.
    "! the refusal of a member by itself, initial if a sub-cube allows it
    METHODS member_refusal
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_check.
    "! whether one sub-cube allows every member of the tuple
    METHODS tuple_allowed
      IMPORTING tuple         TYPE ty_tuple
      RETURNING VALUE(result) TYPE abap_bool.
    CLASS-METHODS refused
      IMPORTING reason        TYPE csequence
                message       TYPE csequence
                !status       TYPE csequence DEFAULT c_status-no_auth
      RETURNING VALUE(result) TYPE ty_check.
ENDCLASS.



CLASS zzxxmla1_cl_bw_auth IMPLEMENTATION.

  METHOD read.
    TYPES ty_iobjnm_range TYPE RANGE OF rsiobjnm.
    TYPES ty_auth_range TYPE RANGE OF rsauth.
    DATA lines TYPE ty_lines.
    lines-provider = to_upper( provider ).
    lines-today = today.

    " the provider's authorization-relevant characteristics, and the special ones that are
    DATA(metadata) = NEW zzxxmla1_cl_bw_provider( )->read( provider ).
    DATA(names) = VALUE ty_iobjnm_range( FOR c IN metadata-characteristics ( sign = 'I' option = 'EQ' low = c-iobjnm ) ).
    IF names IS NOT INITIAL.
      SELECT chanm FROM rsdcha
        WHERE objvers = 'A'
          AND authrelfl = 'X'
          AND chanm IN @names
        ORDER BY chanm ASCENDING
        INTO TABLE @lines-characteristics.
    ENDIF.
    DATA(specials) = VALUE ty_iobjnm_range( sign = 'I' option = 'EQ' ( low = c_special-provider )
                                            ( low = c_special-activity ) ( low = c_special-validity ) ).
    SELECT chanm FROM rsdcha
      WHERE objvers = 'A'
        AND authrelfl = 'X'
        AND chanm IN @specials
      ORDER BY chanm ASCENDING
      INTO TABLE @lines-specials.

    " the user's authorizations: S_RS_AUTH (patterns too) and the direct assignment
    SELECT DISTINCT tctauth FROM rsecval_string
      WHERE objvers = 'A'
      INTO TABLE @DATA(candidates).
    SELECT auth FROM rsecuserauth
      WHERE uname = @user
      INTO TABLE @DATA(direct).
    LOOP AT candidates INTO DATA(candidate).
      AUTHORITY-CHECK OBJECT 'S_RS_AUTH' FOR USER user ID 'BIAUTH' FIELD candidate-tctauth.
      IF sy-subrc = 0 OR line_exists( direct[ auth = candidate-tctauth ] ).
        APPEND candidate-tctauth TO lines-auths.
      ENDIF.
    ENDLOOP.
    IF lines-auths IS INITIAL.
      result = create( lines ).
      RETURN.
    ENDIF.
    DATA(auths) = VALUE ty_auth_range( FOR a IN lines-auths ( sign = 'I' option = 'EQ' low = a ) ).

    SELECT tctauth, tctiobjnm, tctsign, tctoption, tctlow, tcthigh
      FROM rsecval_string
      WHERE objvers = 'A'
        AND tctauth IN @auths
      ORDER BY tctauth ASCENDING, tctiobjnm ASCENDING, tctlow ASCENDING
      INTO TABLE @DATA(values).
    LOOP AT values INTO DATA(value).
      APPEND VALUE #( auth   = value-tctauth
                      iobjnm = value-tctiobjnm
                      sign   = value-tctsign
                      option = value-tctoption
                      low    = value-tctlow
                      high   = value-tcthigh ) TO lines-values.
    ENDLOOP.

    SELECT tctauth, tctiobjnm, tcthienm, tcthievers, tcthiedate, tctniobjnm, tctnode, tctatype, tcttlevel
      FROM rsechie_string
      WHERE objvers = 'A'
        AND tctauth IN @auths
      ORDER BY tctauth ASCENDING, tctiobjnm ASCENDING, tcthienm ASCENDING, tctnode ASCENDING
      INTO TABLE @DATA(hierarchies).
    LOOP AT hierarchies INTO DATA(hierarchy).
      " the values of a line come from the slice valid at its date (today without one)
      DATA(date) = COND d( WHEN hierarchy-tcthiedate IS INITIAL THEN today ELSE hierarchy-tcthiedate ).
      APPEND VALUE #( auth        = hierarchy-tctauth
                      iobjnm      = hierarchy-tctiobjnm
                      hienm       = hierarchy-tcthienm
                      version     = hierarchy-tcthievers
                      node_iobjnm = hierarchy-tctniobjnm
                      node        = hierarchy-tctnode
                      type        = hierarchy-tctatype
                      level       = hierarchy-tcttlevel
                      date        = date ) TO lines-hierarchies.
      IF NOT line_exists( lines-characteristics[ table_line = hierarchy-tctiobjnm ] ).
        CONTINUE.
      ENDIF.
      IF NOT line_exists( lines-slices[ iobjnm  = hierarchy-tctiobjnm
                                        hienm   = hierarchy-tcthienm
                                        version = hierarchy-tcthievers ] ).
        APPEND read_slice( iobjnm   = hierarchy-tctiobjnm
                           hienm    = hierarchy-tcthienm
                           version  = hierarchy-tcthievers
                           key_date = key_date ) TO lines-slices.
      ENDIF.
      IF NOT line_exists( lines-value_slices[ iobjnm  = hierarchy-tctiobjnm
                                              hienm   = hierarchy-tcthienm
                                              version = hierarchy-tcthievers
                                              date    = date ] ).
        APPEND read_slice( iobjnm   = hierarchy-tctiobjnm
                           hienm    = hierarchy-tcthienm
                           version  = hierarchy-tcthievers
                           key_date = date ) TO lines-value_slices.
      ENDIF.
    ENDLOOP.
    result = create( lines ).
  ENDMETHOD.

  METHOD read_slice.
    TYPES: BEGIN OF ty_row,
             nodeid   TYPE rshienodid,
             parentid TYPE rsparent,
             iobjnm   TYPE rsiobjnm,
             nodename TYPE rsshnodenamestr,
             tlevel   TYPE rstlevel,
             link     TYPE rslink,
           END OF ty_row.
    TYPES: BEGIN OF ty_interval,
             nodeid   TYPE rshienodid,
             leaffrom TYPE rsshleaffromstr,
             leafto   TYPE rsshleaftostr,
           END OF ty_interval.
    DATA rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.
    DATA intervals TYPE SORTED TABLE OF ty_interval WITH UNIQUE KEY nodeid.
    DATA hietab TYPE rshietab.
    DATA hintab TYPE rshintab.
    result = VALUE #( iobjnm = iobjnm hienm = hienm version = version date = key_date ).

    SELECT SINGLE hieid FROM rshiedir
      WHERE objvers = 'A'
        AND iobjnm = @iobjnm
        AND hienm = @hienm
        AND version = @version
        AND datefrom <= @key_date
        AND dateto >= @key_date
      INTO @DATA(hieid).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    " a reference characteristic has the hierarchy tables of its basic one
    SELECT SINGLE chabasnm FROM rsdcha WHERE chanm = @iobjnm AND objvers = 'A' INTO @DATA(basic).
    IF basic IS INITIAL.
      basic = iobjnm.
    ENDIF.
    CALL FUNCTION 'RSD_HIETAB_GET_FOR_CHA_BAS'
      EXPORTING
        i_chabasnm = basic
      IMPORTING
        e_hietab   = hietab
        e_hintab   = hintab
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0 OR hietab IS INITIAL.
      RETURN.
    ENDIF.
    SELECT nodeid, parentid, iobjnm, nodename, tlevel, link
      FROM (hietab)
      WHERE hieid = @hieid
        AND objvers = 'A'
      ORDER BY nodeid ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @rows.
    " BW names an interval table also for a characteristic that has none (no intervals allowed)
    IF hintab IS NOT INITIAL.
      SELECT SINGLE tabname FROM dd02l WHERE tabname = @hintab AND as4local = 'A' INTO @hintab.
    ENDIF.
    IF sy-subrc = 0 AND hintab IS NOT INITIAL.
      SELECT nodeid, leaffrom, leafto
        FROM (hintab)
        WHERE hieid = @hieid
          AND objvers = 'A'
        INTO CORRESPONDING FIELDS OF TABLE @intervals.
    ENDIF.
    LOOP AT rows INTO DATA(row).
      DATA(node) = VALUE ty_node( nodeid   = row-nodeid
                                  parentid = row-parentid
                                  iobjnm   = row-iobjnm
                                  name     = row-nodename
                                  level    = row-tlevel
                                  link     = xsdbool( row-link IS NOT INITIAL ) ).
      READ TABLE intervals INTO DATA(interval) WITH TABLE KEY nodeid = row-nodeid.
      IF sy-subrc = 0.
        node-interval = abap_true.
        node-low = interval-leaffrom.
        node-high = interval-leafto.
      ENDIF.
      APPEND node TO result-nodes.
    ENDLOOP.
  ENDMETHOD.

  METHOD create.
    result = NEW #( ).
    result->provider = lines-provider.
    result->characteristics = lines-characteristics.
    DATA(auths) = lines-auths.
    SORT auths BY table_line.
    DELETE ADJACENT DUPLICATES FROM auths COMPARING table_line.
    LOOP AT auths INTO DATA(name).
      DATA(values) = VALUE ty_value_lines( FOR v IN lines-values WHERE ( auth = name ) ( v ) ).
      DATA(hierarchies) = VALUE ty_hierarchy_lines( FOR h IN lines-hierarchies WHERE ( auth = name ) ( h ) ).

      " the special characteristics: the provider, display, valid today
      DATA(applies) = abap_true.
      LOOP AT lines-specials INTO DATA(special).
        DATA(admitted) = SWITCH string( special
                                        WHEN c_special-provider THEN lines-provider
                                        WHEN c_special-activity THEN c_display
                                        ELSE |{ lines-today }| ).
        DATA(ranges) = VALUE ty_ranges( FOR v IN values WHERE ( iobjnm = special )
                                        ( sign = v-sign option = v-option low = v-low high = v-high ) ).
        IF ranges IS INITIAL OR in_ranges( value = admitted ranges = ranges ) = abap_false.
          applies = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF applies = abap_false.
        CONTINUE.
      ENDIF.

      " an applying authorization with a variable: not authorized at all
      LOOP AT values TRANSPORTING NO FIELDS
           WHERE iobjnm <> c_special-provider AND iobjnm <> c_special-activity AND iobjnm <> c_special-validity
             AND ( low CP '$*' OR high CP '$*' ).
        result->variable = abap_true.
      ENDLOOP.
      LOOP AT hierarchies TRANSPORTING NO FIELDS WHERE node CP '$*'.
        result->variable = abap_true.
      ENDLOOP.

      " every authorization-relevant characteristic needs a line
      DATA(subcube) = VALUE ty_subcube( auth = name ).
      DATA present TYPE abap_bool.
      LOOP AT lines-characteristics INTO DATA(characteristic).
        DATA(part) = part( EXPORTING iobjnm      = characteristic
                                     values      = values
                                     hierarchies  = hierarchies
                                     slices       = lines-slices
                                     value_slices = lines-value_slices
                           IMPORTING present      = present ).
        IF present = abap_false.
          applies = abap_false.
          EXIT.
        ENDIF.
        INSERT part INTO TABLE subcube-parts.
      ENDLOOP.
      IF applies = abap_true.
        APPEND subcube TO result->subcubes.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD part.
    DATA(characteristic) = iobjnm.
    result-iobjnm = characteristic.
    present = abap_false.
    DATA(excluding) = abap_false.
    LOOP AT values INTO DATA(value) WHERE iobjnm = characteristic.
      present = abap_true.
      IF value-sign = 'E'.
        excluding = abap_true.
      ENDIF.
      IF value-sign = 'I' AND value-option = 'CP' AND value-low = `*`.
        result-all = abap_true.
        result-aggregate = abap_true.
      ELSEIF value-sign = 'I' AND value-option = 'EQ' AND value-low = `:`.
        result-aggregate = abap_true.
      ELSEIF is_variable( value-low ) = abap_false AND is_variable( value-high ) = abap_false.
        APPEND VALUE #( sign   = value-sign
                        option = value-option
                        low    = COND #( WHEN value-option = 'CP' THEN value-low ELSE normalized( value-low ) )
                        high   = normalized( value-high ) ) TO result-ranges.
      ENDIF.
    ENDLOOP.
    " CP * with an exclusion is not everything
    IF excluding = abap_true AND result-all = abap_true.
      result-all = abap_false.
      APPEND VALUE #( sign = 'I' option = 'CP' low = `*` ) TO result-ranges.
    ENDIF.

    LOOP AT hierarchies INTO DATA(line) WHERE iobjnm = characteristic.
      present = abap_true.
      IF is_variable( line-node ) = abap_true.
        CONTINUE.
      ENDIF.
      DATA(slice) = VALUE ty_slice( slices[ iobjnm = characteristic hienm = line-hienm version = line-version ]
                                    DEFAULT VALUE #( iobjnm = characteristic hienm = line-hienm version = line-version ) ).
      DATA(cover) = cover( line = line slice = slice ).
      " the values the line authorizes are those of its own date's slice, whatever the key date
      READ TABLE value_slices INTO DATA(value_slice)
           WITH KEY iobjnm = characteristic hienm = line-hienm version = line-version date = line-date.
      IF sy-subrc = 0.
        APPEND LINES OF cover( line = line slice = value_slice )-ranges TO result-ranges.
      ELSE.
        APPEND LINES OF cover-ranges TO result-ranges.
      ENDIF.
      READ TABLE result-hierarchies ASSIGNING FIELD-SYMBOL(<hierarchy>)
           WITH TABLE KEY hienm = line-hienm version = line-version.
      IF sy-subrc <> 0.
        INSERT VALUE #( hienm = line-hienm version = line-version ) INTO TABLE result-hierarchies
               ASSIGNING <hierarchy>.
      ENDIF.
      IF line-type = '3' OR line-type = '4'.
        <hierarchy>-complete = abap_true.
      ENDIF.
      LOOP AT cover-nodes INTO DATA(node).
        READ TABLE <hierarchy>-nodes ASSIGNING FIELD-SYMBOL(<node>)
             WITH TABLE KEY iobjnm = node-iobjnm name = node-name.
        IF sy-subrc = 0.
          IF node-expandable = abap_true.
            <node>-expandable = abap_true.
          ENDIF.
        ELSE.
          INSERT node INTO TABLE <hierarchy>-nodes.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD cover.
    TYPES: BEGIN OF ty_step,
             index  TYPE i,
             level  TYPE i,
             parent TYPE i,
           END OF ty_step.
    DATA stack TYPE STANDARD TABLE OF ty_step WITH EMPTY KEY.
    DATA visited TYPE SORTED TABLE OF i WITH UNIQUE KEY table_line.

    " where the line starts: the roots for the complete hierarchy, else its node (the one that is no link first)
    DATA(complete) = xsdbool( line-type = '3' OR line-type = '4' ).
    DATA(start) = 0.
    LOOP AT slice-nodes INTO DATA(node).
      IF complete = abap_true.
        IF node-parentid = 0.
          INSERT VALUE #( index = sy-tabix level = node-level ) INTO stack INDEX 1.
        ENDIF.
      ELSEIF node-iobjnm = line-node_iobjnm AND node-name = line-node
             AND ( start = 0 OR node-link = abap_false ).
        start = sy-tabix.
        IF node-link = abap_false.
          EXIT.
        ENDIF.
      ENDIF.
    ENDLOOP.
    IF start > 0.
      APPEND VALUE #( index = start level = slice-nodes[ start ]-level ) TO stack.
    ENDIF.

    " depth first, the children pushed in reverse so that the subtree is walked in the hierarchy's order
    WHILE stack IS NOT INITIAL.
      DATA(step) = stack[ lines( stack ) ].
      DELETE stack INDEX lines( stack ).
      node = slice-nodes[ step-index ].
      DATA(expandable) = SWITCH abap_bool( line-type
                                           WHEN '0' THEN abap_false
                                           WHEN '2' THEN xsdbool( step-level < line-level )
                                           ELSE abap_true ).
      DATA(parent) = COND ty_node( WHEN step-parent > 0 THEN slice-nodes[ step-parent ] ).
      INSERT VALUE #( iobjnm        = node-iobjnm
                      name          = node-name
                      level         = step-level
                      expandable    = expandable
                      parent_iobjnm = parent-iobjnm
                      parent_name   = parent-name ) INTO TABLE result-nodes.
      IF node-interval = abap_true.
        APPEND VALUE #( sign = 'I' option = 'BT' low = node-low high = node-high ) TO result-ranges.
      ELSEIF node-iobjnm = slice-iobjnm.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = normalized( node-name ) ) TO result-ranges.
      ENDIF.
      IF expandable = abap_false.
        CONTINUE.
      ENDIF.
      " the children of the node, and of a link node those of the node of its name that is no link
      DATA(parents) = VALUE int4_table( ( node-nodeid ) ).
      IF node-link = abap_true.
        LOOP AT slice-nodes INTO DATA(original)
             WHERE iobjnm = node-iobjnm AND name = node-name AND link = abap_false.
          APPEND original-nodeid TO parents.
        ENDLOOP.
      ENDIF.
      DATA(children) = VALUE int4_table( ).
      LOOP AT slice-nodes INTO DATA(child) WHERE parentid <> 0.
        DATA(child_index) = sy-tabix.
        IF line_exists( parents[ table_line = child-parentid ] ).
          INSERT child_index INTO TABLE visited.
          IF sy-subrc = 0.
            APPEND child_index TO children.
          ENDIF.
        ENDIF.
      ENDLOOP.
      DATA(i) = lines( children ).
      WHILE i > 0.
        APPEND VALUE #( index = children[ i ] level = step-level + 1 parent = step-index ) TO stack.
        i = i - 1.
      ENDWHILE.
    ENDWHILE.
  ENDMETHOD.

  METHOD in_ranges.
    result = abap_false.
    LOOP AT ranges INTO DATA(range) WHERE sign = 'I'.
      IF in_range( value = value range = range ) = abap_true.
        result = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF result = abap_true.
      LOOP AT ranges INTO range WHERE sign = 'E'.
        IF in_range( value = value range = range ) = abap_true.
          result = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD in_range.
    DATA(key) = normalized( value ).
    CASE range-option.
      WHEN 'EQ'.
        result = xsdbool( key = range-low ).
      WHEN 'BT'.
        result = xsdbool( key >= range-low AND key <= range-high ).
      WHEN 'CP'.
        result = pattern_matches( value = key pattern = range-low ).
      WHEN OTHERS.
        result = abap_false.
    ENDCASE.
  ENDMETHOD.

  METHOD pattern_matches.
    DATA(regex) = escape( val = pattern format = cl_abap_format=>e_regex ).
    regex = replace( val = regex sub = `\*` with = `.*` occ = 0 ).
    regex = replace( val = regex sub = `\+` with = `.` occ = 0 ).
    result = xsdbool( matches( val = value regex = regex ) ).
    IF result = abap_true OR value IS INITIAL OR value CN `0123456789`.
      RETURN.
    ENDIF.
    " the leading digits as a number of the value's length (NUMC): 01* is 001*
    DATA(digits) = find( val = pattern regex = `[^0-9]` ).
    DATA(width) = strlen( value ).
    IF digits <= 0 OR digits >= width.
      RETURN.
    ENDIF.
    DATA(number) = substring( val = pattern len = digits ).
    result = pattern_matches( value   = value
                              pattern = |{ number WIDTH = width ALIGN = RIGHT PAD = '0' }{
                                         substring( val = pattern off = digits ) }| ).
  ENDMETHOD.

  METHOD normalized.
    result = COND #( WHEN value = `#` THEN `` ELSE value ).
  ENDMETHOD.

  METHOD is_variable.
    result = xsdbool( value CP '$*' ).
  ENDMETHOD.

  METHOD current_user.
    CALL FUNCTION 'RSEC_GET_USERNAME'
      IMPORTING
        e_username = result.
  ENDMETHOD.

  METHOD check.
    result = check_members( VALUE #( FOR t IN selection FOR m IN t ( m ) ) ).
    IF result-status <> c_status-allowed OR unrestricted( ) = abap_true.
      RETURN.
    ENDIF.
    LOOP AT selection INTO DATA(tuple).
      IF tuple_allowed( tuple ) = abap_false.
        result = refused( reason = c_reason-combination message = `You do not have sufficient authorization` ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_members.
    IF variable = abap_true.
      result = refused( reason  = c_reason-variable
                        message = |You do not have sufficient authorization: an analysis authorization with a | &&
                                  |variable applies to the InfoProvider { provider }, and variables are not supported| ).
      RETURN.
    ENDIF.
    IF subcubes IS INITIAL.
      result = refused( reason  = c_reason-provider
                        message = |You do not have sufficient authorization for the InfoProvider { provider }| ).
      RETURN.
    ENDIF.
    IF unrestricted( ) = abap_true.
      result-status = c_status-allowed.
      RETURN.
    ENDIF.

    " the members the query names first, as BW resolves them before it reads, then every other one
    DO 2 TIMES.
      DATA(naming) = xsdbool( sy-index = 1 ).
      LOOP AT members INTO DATA(member) WHERE named = naming.
        result = member_refusal( member ).
        IF result IS NOT INITIAL.
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDDO.
    result-status = c_status-allowed.
  ENDMETHOD.

  METHOD member_refusal.
    IF member-kind = c_kind-aggregate OR NOT line_exists( characteristics[ table_line = member-iobjnm ] ).
      RETURN.
    ENDIF.
    DATA(values) = abap_false.
    DATA(lines_on_hierarchy) = abap_false.
    LOOP AT subcubes INTO DATA(subcube).
      DATA(part) = subcube-parts[ iobjnm = member-iobjnm ].
      IF admits( part = part member = member ) = abap_true.
        RETURN.
      ENDIF.
      IF part-all = abap_true OR part-ranges IS NOT INITIAL.
        values = abap_true.
      ENDIF.
      IF line_exists( part-hierarchies[ hienm = member-hienm version = member-version ] ).
        lines_on_hierarchy = abap_true.
      ENDIF.
    ENDLOOP.

    CASE member-kind.
      WHEN c_kind-value.
        IF values = abap_false.
          result = refused( reason  = c_reason-no_values
                            message = |You do not have analysis authorization for any char. values of char. {
                                      member-iobjnm }| ).
        ELSEIF member-named = abap_true.
          result = refused( reason  = c_reason-value
                            status  = c_status-unknown
                            message = |Value { COND string( WHEN normalized( member-value ) IS INITIAL THEN `#`
                                                            ELSE member-value ) } for characteristic {
                                      member-iobjnm } unknown| ).
        ELSE.
          result = refused( reason = c_reason-combination message = `You do not have sufficient authorization` ).
        ENDIF.
      WHEN c_kind-node.
        DATA(hierarchy) = |{ member-hienm }{ COND string( WHEN member-version IS NOT INITIAL
                                                          THEN | version { member-version }| ) }|.
        IF lines_on_hierarchy = abap_false.
          result = refused( reason  = c_reason-hierarchy
                            message = |No authority for the node from characteristic { member-iobjnm }, hierarchy {
                                      hierarchy }| ).
        ELSE.
          result = refused( reason  = c_reason-node
                            message = |Hierarchy node { member-value } of { hierarchy } not authorized| ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD tuple_allowed.
    LOOP AT subcubes INTO DATA(subcube).
      result = abap_true.
      LOOP AT subcube-parts INTO DATA(part).
        DATA(found) = abap_false.
        LOOP AT tuple INTO DATA(member) WHERE iobjnm = part-iobjnm.
          found = abap_true.
          IF admits( part = part member = member ) = abap_false.
            result = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
        " a characteristic not in the tuple is aggregated
        IF found = abap_false AND part-aggregate = abap_false.
          result = abap_false.
        ENDIF.
        IF result = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
    result = abap_false.
  ENDMETHOD.

  METHOD admits.
    IF part-all = abap_true.
      result = abap_true.
      RETURN.
    ENDIF.
    CASE member-kind.
      WHEN c_kind-aggregate.
        result = part-aggregate.
      WHEN c_kind-value.
        result = in_ranges( value = member-value ranges = part-ranges ).
      WHEN c_kind-node.
        READ TABLE part-hierarchies INTO DATA(hierarchy)
             WITH TABLE KEY hienm = member-hienm version = member-version.
        result = xsdbool( sy-subrc = 0
                          AND line_exists( hierarchy-nodes[ iobjnm = member-node_iobjnm name = member-value ] ) ).
    ENDCASE.
  ENDMETHOD.

  METHOD unrestricted.
    LOOP AT subcubes INTO DATA(subcube).
      result = abap_true.
      LOOP AT subcube-parts TRANSPORTING NO FIELDS WHERE all = abap_false.
        result = abap_false.
        EXIT.
      ENDLOOP.
      IF result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD hierarchy_access.
    LOOP AT subcubes INTO DATA(subcube).
      READ TABLE subcube-parts INTO DATA(part) WITH TABLE KEY iobjnm = iobjnm.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF part-all = abap_true.
        result-all = abap_true.
      ENDIF.
      READ TABLE part-hierarchies INTO DATA(hierarchy) WITH TABLE KEY hienm = hienm version = version.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      result-lines = abap_true.
      IF hierarchy-complete = abap_true.
        result-complete = abap_true.
      ENDIF.
      LOOP AT hierarchy-nodes INTO DATA(node).
        READ TABLE result-nodes ASSIGNING FIELD-SYMBOL(<node>) WITH TABLE KEY iobjnm = node-iobjnm name = node-name.
        IF sy-subrc = 0.
          IF node-expandable = abap_true.
            <node>-expandable = abap_true.
          ENDIF.
        ELSE.
          INSERT node INTO TABLE result-nodes.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    IF result-all = abap_true.
      CLEAR result-nodes.
      RETURN.
    ENDIF.
    LOOP AT result-nodes ASSIGNING <node>.
      <node>-top = xsdbool( NOT line_exists( result-nodes[ iobjnm = <node>-parent_iobjnm name = <node>-parent_name ] ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD applying.
    result = VALUE #( FOR s IN subcubes ( s-auth ) ).
  ENDMETHOD.

  METHOD refused.
    result = VALUE #( status = status reason = reason message = message ).
  ENDMETHOD.

ENDCLASS.
