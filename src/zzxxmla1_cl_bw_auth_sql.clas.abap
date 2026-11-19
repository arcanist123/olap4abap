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
"! The check of a query's selection against a user's analysis authorizations in HANA (docs/next-steps.md, Now:
"! analysis authorisations, Decisions of 2026-10-24; The selection as a product per characteristic, and one statement
"! per provider): the answers of ZZXXMLA1_CL_BW_AUTH's check, with no hierarchy expanded in ABAP.
"! The profile is the user's region per node (ZZXXMLA1_CL_BW_AUTH=>profile, read without expansion): per applying
"! authorization and authorization-relevant characteristic its flags (all, aggregate) and flat ranges, and its
"! hierarchy lines by name, each with two copies of its hierarchy (ZZXXMLA1_CL_BW_HIERARCHY_COPY): the slice valid at
"! the key date (the nodes the line shows) and the slice valid at the line's date (the values it authorizes). The
"! copies are made when the profile is read, and the tables of every hierarchy characteristic of the provider
"! (create_tables), never by a check.
"! The selection is the product of the query's members per characteristic, as BW's MDX on InfoProviders checks it
"! (mvp-scope.md, BW's rules): one member list per authorization-relevant characteristic, the members of every factor
"! (the slicer, the axes, the subselects' axes) of it, its aggregate where the query names none; the members the query
"! names but shows in no tuple (the node of a Children) are checked alone, outside the product.
"! One statement answers it, its text the same for every query, user and key date of a provider (its data bound as
"! JSON; only the branches over the provider's copy tables are the provider's): per member the authorizations that
"! admit it as a bit mask, the members of a characteristic grouped by mask into classes, and the members no
"! authorization admits with BW's reason. An authorization is a sub-cube, so the product is authorized exactly when
"! every combination of one class per characteristic has a common bit; that search runs here, over the classes,
"! never over the product. A line is expanded on the path table of its copy: its node's occurrences are the path rows
"! whose level member has the line's node name and InfoObject, the occurrence's own row (TLEVEL = DEPTH) names what the
"! line shows; type 0 the node itself, 1 its subtree, 2 its subtree down to the line's level, 3 (and 4) every
"! occurrence (the roots' rows, TLEVEL 1) and, where the hierarchy shows it, the not-assigned node REST_H with its
"! values, which are no path rows. A leaf of the copy is named by the characteristic and its key, so a line on a leaf
"! matches by name too, and the values a line authorizes are its leaves' keys. Values are matched by key: EQ and BT as
"! BW compares them, CP as LIKE (* %, + _, the others escaped) and, on a key of digits (NUMC), with the pattern's
"! leading digits as a number of the key's length; the not-assigned value is the key ''. The provider, a variable and
"! an unrestricted user (0BI_ALL) are answered before, without a statement.
CLASS zzxxmla1_cl_bw_auth_sql DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    "! the factors of a query's selection: per factor its tuples; a tuple of the query is one of each
    TYPES ty_factors TYPE STANDARD TABLE OF zzxxmla1_cl_bw_auth=>ty_selection WITH EMPTY KEY.
    "! a copy of a hierarchy slice as the statement reads it: the basic characteristic whose tables hold it, BW's
    "! HIESID and SVER (hiesid 0: the slice has none at the date), whether it shows the not-assigned node REST_H, and
    "! the SID of that node
    TYPES: BEGIN OF ty_copy,
             basic        TYPE rsiobjnm,
             hiesid       TYPE i,
             sver         TYPE string,
             rest_shown   TYPE abap_bool,
             rest_top_sid TYPE i,
           END OF ty_copy.
    "! a hierarchy line with the copy of the slice at the key date and the one at its own date
    TYPES: BEGIN OF ty_line,
             line       TYPE zzxxmla1_cl_bw_auth=>ty_hierarchy_line,
             key_copy   TYPE ty_copy,
             value_copy TYPE ty_copy,
           END OF ty_line.
    TYPES ty_lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    "! the tables of a hierarchy characteristic of the provider (its basic one): the copies' path table, their
    "! not-assigned view as closure (the closure table's rows and those under REST_H, which the table has not), the
    "! SID table and the expression of a key there (alias s) that name the values of REST_H (initial: not named)
    TYPES: BEGIN OF ty_hierarchy_tables,
             basic     TYPE rsiobjnm,
             path      TYPE tabname,
             closure   TYPE tabname,
             sid_table TYPE tabname,
             leaf_name TYPE string,
           END OF ty_hierarchy_tables.
    TYPES ty_t_hierarchy_tables TYPE STANDARD TABLE OF ty_hierarchy_tables WITH EMPTY KEY.
    "! the profile: the characteristics, the flat parts, the hierarchy lines with their copies and the tables of the
    "! provider's hierarchy characteristics (the branches of the statement)
    TYPES: BEGIN OF ty_profile,
             characteristics TYPE zzxxmla1_cl_bw_auth=>ty_characteristics,
             flats           TYPE zzxxmla1_cl_bw_auth=>ty_flats,
             lines           TYPE ty_lines,
             tables          TYPE ty_t_hierarchy_tables,
           END OF ty_profile.
    TYPES: BEGIN OF ty_statement,
             sql    TYPE string,
             params TYPE zzxxmla1_cl_sql=>ty_t_param,
           END OF ty_statement.
    "! a member with the authorizations that admit it as bits (numbered per statement; 0: none) and, with mask 0,
    "! BW's reason
    TYPES: BEGIN OF ty_masked,
             member TYPE zzxxmla1_cl_bw_auth=>ty_member,
             mask   TYPE int8,
             reason TYPE c LENGTH 12,
           END OF ty_masked.
    TYPES ty_t_masked TYPE STANDARD TABLE OF ty_masked WITH EMPTY KEY.

    "! The authorizations a mask has room for: a bit each in a BIGINT, the sign bit left out.
    CONSTANTS c_max_auths TYPE i VALUE 63.

    "! The check of the user on the provider at the key date: the region read without expansion, its copies made.
    CLASS-METHODS read
      IMPORTING !user         TYPE xubname
                provider      TYPE csequence
                key_date      TYPE d DEFAULT zzxxmla1_cl_bw_auth=>c_key_date
                today         TYPE d DEFAULT sy-datum
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_bw_auth_sql
      RAISING   zzxxmla1_cx_bw_provider.
    "! The check of a region and a given profile, for the unit tests.
    CLASS-METHODS create
      IMPORTING region        TYPE REF TO zzxxmla1_cl_bw_auth
                profile       TYPE ty_profile
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_bw_auth_sql.

    "! Whether the query's selection, its tuples as one factor, is in the region (ZZXXMLA1_CL_BW_AUTH's check).
    METHODS check
      IMPORTING selection     TYPE zzxxmla1_cl_bw_auth=>ty_selection
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! Whether the product of the factors' members per characteristic is in the region; members only if a factor
    "! has no tuple.
    METHODS check_product
      IMPORTING factors       TYPE ty_factors
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! The check of a query: the members it names, also those its tuples do not show (the node of a Children), then
    "! the product of its factors' members per characteristic; members only if a factor has no tuple.
    METHODS check_query
      IMPORTING factors       TYPE ty_factors
                members       TYPE zzxxmla1_cl_bw_auth=>ty_tuple
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! The check of members without their product (ZZXXMLA1_CL_BW_AUTH's check_members).
    METHODS check_members
      IMPORTING members       TYPE zzxxmla1_cl_bw_auth=>ty_tuple
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! The authorizations that apply to the provider.
    METHODS applying
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_auths.
    "! What the user may see of the hierarchies of each authorization-relevant characteristic, by which the members of
    "! a BW hierarchy are restricted (step 5b): all where an applying authorization has all values of it, else the
    "! hierarchy lines of the applying authorizations on it (as ZZXXMLA1_CL_BW_AUTH's hierarchy_access, by name); none
    "! for an unrestricted user and where no authorization applies (every selection is refused then).
    METHODS visibles
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_hierarchy_copy=>ty_t_visible.
    "! Per member of an authorization-relevant characteristic the mask of the authorizations that admit it and, with
    "! mask 0, BW's reason (the aggregate's: combination); one statement, members of other characteristics left out.
    "! Meaningful only without provider_refusal and for a restricted user (the profile is empty otherwise).
    METHODS masks
      IMPORTING members       TYPE zzxxmla1_cl_bw_auth=>ty_tuple
      RETURNING VALUE(result) TYPE ty_t_masked.
    "! The provider's authorization-relevant characteristics.
    METHODS characteristics
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_characteristics.
    "! Whether one authorization allows everything (0BI_ALL): no check is needed.
    METHODS unrestricted
      RETURNING VALUE(result) TYPE abap_bool.
    "! The refusal of every selection (no authorization applies to the provider, or one has a variable); initial if
    "! neither.
    METHODS provider_refusal
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! a member of the request: the query's member, the key it is matched by (a value's '' for #) and the position of
    "! its characteristic in the product (0: checked alone)
    TYPES: BEGIN OF ty_request_member,
             member TYPE zzxxmla1_cl_bw_auth=>ty_member,
             key    TYPE string,
             pos    TYPE i,
           END OF ty_request_member.
    TYPES ty_request_members TYPE STANDARD TABLE OF ty_request_member WITH EMPTY KEY.
    "! the request: the distinct members of the authorization-relevant characteristics in the order the query's tuples
    "! show them first (the last factor fastest); product: their product is checked (every factor has a tuple), each
    "! characteristic then has a member in it, its aggregate where the query names none
    TYPES: BEGIN OF ty_request,
             members TYPE ty_request_members,
             product TYPE abap_bool,
           END OF ty_request.
    "! a column of a derived table of bound values: its name (also its key in the JSON) and SQL type
    TYPES: BEGIN OF ty_column,
             name TYPE string,
             type TYPE string,
           END OF ty_column.
    TYPES ty_columns TYPE STANDARD TABLE OF ty_column WITH EMPTY KEY.
    TYPES ty_rows TYPE STANDARD TABLE OF zzxxmla1_cl_sql=>ty_t_param WITH EMPTY KEY.
    "! BW's CP pattern as LIKE parts: the pattern, and of a pattern that starts with digits these digits and the
    "! pattern of the rest (for a NUMC key)
    TYPES: BEGIN OF ty_like,
             pattern TYPE string,
             number  TYPE string,
             rest    TYPE string,
           END OF ty_like.
    "! a mask as bits: BIT-AND needs a byte field
    TYPES ty_mask TYPE x LENGTH 8.
    TYPES ty_masks TYPE STANDARD TABLE OF ty_mask WITH EMPTY KEY.
    "! per characteristic of the product the masks of its classes
    TYPES ty_dimensions TYPE STANDARD TABLE OF ty_masks WITH EMPTY KEY.

    CONSTANTS c_key_copy TYPE c LENGTH 1 VALUE 'K'.
    CONSTANTS c_value_copy TYPE c LENGTH 1 VALUE 'V'.
    CONSTANTS c_every TYPE ty_mask VALUE 'FFFFFFFFFFFFFFFF'.
    "! the rows of the statement's answer (ROW_TYPE)
    CONSTANTS: BEGIN OF c_row,
                 class   TYPE string VALUE `CLASS`,
                 member  TYPE string VALUE `MEMBER`,
                 refused TYPE string VALUE `REFUSED`,
               END OF c_row.

    DATA region TYPE REF TO zzxxmla1_cl_bw_auth.
    DATA profile TYPE ty_profile.

    "! the basic characteristic of a characteristic: whose hierarchies and copies it has
    CLASS-METHODS basic_of
      IMPORTING iobjnm        TYPE rsiobjnm
      RETURNING VALUE(result) TYPE rsiobjnm.
    "! the copy of the slice of a line's hierarchy valid at the date, initial if BW has none then
    CLASS-METHODS copy_of
      IMPORTING copies        TYPE REF TO zzxxmla1_cl_bw_hierarchy_copy
                !line         TYPE zzxxmla1_cl_bw_auth=>ty_hierarchy_line
                !date         TYPE d
      RETURNING VALUE(result) TYPE ty_copy.
    "! the tables of the characteristics' basic ones that have hierarchies, created where missing (commits)
    CLASS-METHODS hierarchy_tables
      IMPORTING copies          TYPE REF TO zzxxmla1_cl_bw_hierarchy_copy
                characteristics TYPE zzxxmla1_cl_bw_auth=>ty_characteristics
      RETURNING VALUE(result)   TYPE ty_t_hierarchy_tables.
    "! the request of the factors' members, or of members alone
    CLASS-METHODS request
      IMPORTING characteristics TYPE zzxxmla1_cl_bw_auth=>ty_characteristics
                factors         TYPE ty_factors OPTIONAL
                members         TYPE zzxxmla1_cl_bw_auth=>ty_tuple OPTIONAL
      RETURNING VALUE(result)   TYPE ty_request.
    "! the statement: rows ROW_TYPE (CLASS, MEMBER with list_members, REFUSED), POS, MASK, M (a class's first member),
    "! MEMBER_COUNT and REASON
    CLASS-METHODS check_statement
      IMPORTING profile       TYPE ty_profile
                request       TYPE ty_request
                list_members  TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE ty_statement.
    "! section 1 of the statement: the inputs as derived tables of bound JSON
    CLASS-METHODS inputs_sql
      IMPORTING profile       TYPE ty_profile
                request       TYPE ty_request
      CHANGING  params        TYPE zzxxmla1_cl_sql=>ty_t_param
      RETURNING VALUE(result) TYPE string_table.
    "! section 2 of the statement: the copies' path rows and their not-assigned members, a branch per hierarchy
    "! characteristic of the provider
    CLASS-METHODS copies_sql
      IMPORTING tables        TYPE ty_t_hierarchy_tables
      RETURNING VALUE(result) TYPE string_table.
    "! sections 3 to 6 and the answer: what the lines show, the admissions, the masks and classes, the refusals
    CLASS-METHODS check_sql
      RETURNING VALUE(result) TYPE string_table.
    "! A derived table of bound values: the rows as one JSON parameter (an array of objects, keyed by the columns'
    "! names) read by JSON_TABLE, so the statement's text is the same whatever the number of rows and HANA compiles
    "! it once (a UNION ALL of a SELECT per row made a new statement per number of rows, compiled in seconds and
    "! evicting other plans from the plan cache); no rows: the array [], an empty table.
    CLASS-METHODS values_sql
      IMPORTING columns       TYPE ty_columns
                !rows         TYPE ty_rows
      CHANGING  params        TYPE zzxxmla1_cl_sql=>ty_t_param
      RETURNING VALUE(result) TYPE string.
    "! the rows of values_sql as a JSON array of objects, a value a number (type i, int8) or a string
    CLASS-METHODS values_json
      IMPORTING columns       TYPE ty_columns
                !rows         TYPE ty_rows
      RETURNING VALUE(result) TYPE string.
    "! BW's pattern (CP) as LIKE patterns with the escape character \
    CLASS-METHODS like
      IMPORTING pattern       TYPE csequence
      RETURNING VALUE(result) TYPE ty_like.
    CLASS-METHODS like_pattern
      IMPORTING pattern       TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! the answer of the statement's rows: the first refused member (a member before an aggregate, a named one
    "! first), else a combination of classes without a common authorization, else allowed
    CLASS-METHODS answer
      IMPORTING !rows         TYPE zzxxmla1_cl_sql=>ty_t_row
                request       TYPE ty_request
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! whether a combination of one class per dimension from depth on, with the masks before it ANDed to mask, has
    "! no common authorization
    CLASS-METHODS hole
      IMPORTING dimensions    TYPE ty_dimensions
                !depth        TYPE i
                !mask         TYPE ty_mask
      RETURNING VALUE(result) TYPE abap_bool.
    "! the check of a request: the provider's refusal, an unrestricted user, else the statement
    METHODS answered
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! the statement's rows for the request
    METHODS rows_of
      IMPORTING request       TYPE ty_request
                list_members  TYPE abap_bool
      RETURNING VALUE(result) TYPE zzxxmla1_cl_sql=>ty_t_row.
ENDCLASS.



CLASS zzxxmla1_cl_bw_auth_sql IMPLEMENTATION.

  METHOD read.
    DATA(region) = zzxxmla1_cl_bw_auth=>read( user     = user
                                              provider = provider
                                              key_date = key_date
                                              today    = today
                                              expand   = abap_false ).
    DATA(profile) = VALUE ty_profile( ).
    IF region->provider_refusal( ) IS INITIAL AND region->unrestricted( ) = abap_false.
      DATA(base) = region->profile( ).
      profile-characteristics = base-characteristics.
      profile-flats = base-flats.
      DATA(copies) = NEW zzxxmla1_cl_bw_hierarchy_copy( ).
      " the tables of every hierarchy characteristic of the provider first, whether a line names it or not, so the
      " statement is the provider's: creating them is a DDIC activation that commits
      profile-tables = hierarchy_tables( copies = copies characteristics = base-characteristics ).
      LOOP AT base-hierarchies INTO DATA(line).
        " an expired line (validity 0 after its date) shows no node: no copy of the key date
        APPEND VALUE #( line       = line
                        key_copy   = COND #( WHEN line-expired = abap_false
                                             THEN copy_of( copies = copies line = line date = key_date ) )
                        value_copy = copy_of( copies = copies line = line date = line-date ) ) TO profile-lines.
      ENDLOOP.
    ENDIF.
    result = create( region = region profile = profile ).
  ENDMETHOD.

  METHOD create.
    result = NEW #( ).
    result->region = region.
    result->profile = profile.
  ENDMETHOD.

  METHOD basic_of.
    " a reference characteristic has the hierarchies of its basic one
    SELECT SINGLE chabasnm FROM rsdcha WHERE chanm = @iobjnm AND objvers = 'A' INTO @result.
    IF result IS INITIAL.
      result = iobjnm.
    ENDIF.
  ENDMETHOD.

  METHOD hierarchy_tables.
    LOOP AT characteristics INTO DATA(characteristic).
      DATA(basic) = basic_of( characteristic ).
      IF line_exists( result[ basic = basic ] ).
        CONTINUE.
      ENDIF.
      SELECT SINGLE hieid FROM rshiedir WHERE objvers = 'A' AND iobjnm = @basic INTO @DATA(hieid) ##NEEDED.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      DATA(tables) = copies->create_tables( basic ).
      DATA(leaf) = zzxxmla1_cl_bw_hierarchy_copy=>leaf_source( basic ).
      APPEND VALUE #( basic     = basic
                      path      = tables-path
                      closure   = tables-rest_view
                      sid_table = leaf-sid_table
                      leaf_name = leaf-leaf_name ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD copy_of.
    DATA(basic) = basic_of( line-iobjnm ).
    SELECT SINGLE hieid FROM rshiedir
      WHERE objvers = 'A'
        AND iobjnm = @basic
        AND hienm = @line-hienm
        AND version = @line-version
        AND datefrom <= @date
        AND dateto >= @date
      INTO @DATA(hieid) ##NEEDED.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(hierarchy) = copies->current( characteristic = basic
                                       name           = line-hienm
                                       version        = line-version
                                       key_date       = date ).
    result = VALUE #( basic        = basic
                      hiesid       = hierarchy-hiesid
                      sver         = condense( CONV string( hierarchy-sver ) )
                      rest_shown   = hierarchy-rest_shown
                      rest_top_sid = hierarchy-rest_top_sid ).
  ENDMETHOD.

  METHOD applying.
    result = region->applying( ).
  ENDMETHOD.

  METHOD visibles.
    IF region->provider_refusal( ) IS NOT INITIAL OR region->unrestricted( ) = abap_true.
      RETURN.
    ENDIF.
    LOOP AT profile-characteristics INTO DATA(characteristic).
      DATA(visible) = VALUE zzxxmla1_cl_bw_hierarchy_copy=>ty_visible(
        characteristic = characteristic
        all            = xsdbool( line_exists( profile-flats[ iobjnm = characteristic all = abap_true ] ) ) ).
      IF visible-all = abap_false.
        LOOP AT profile-lines INTO DATA(line) WHERE line-iobjnm = characteristic AND line-expired = abap_false.
          DATA(visible_line) = VALUE zzxxmla1_cl_bw_hierarchy_copy=>ty_visible_line(
            name = line-line-hienm version = line-line-version node_iobj = line-line-node_iobjnm
            node = line-line-node type = line-line-type level = line-line-level ).
          IF NOT line_exists( visible-lines[ table_line = visible_line ] ).
            APPEND visible_line TO visible-lines.
          ENDIF.
        ENDLOOP.
      ENDIF.
      APPEND visible TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD check.
    result = check_product( VALUE #( ( selection ) ) ).
  ENDMETHOD.

  METHOD check_product.
    result = answered( request( characteristics = profile-characteristics factors = factors ) ).
  ENDMETHOD.

  METHOD check_members.
    result = answered( request( characteristics = profile-characteristics members = members ) ).
  ENDMETHOD.

  METHOD check_query.
    result = answered( request( characteristics = profile-characteristics factors = factors members = members ) ).
  ENDMETHOD.

  METHOD answered.
    result = region->provider_refusal( ).
    IF result IS NOT INITIAL.
      RETURN.
    ENDIF.
    result-status = zzxxmla1_cl_bw_auth=>c_status-allowed.
    IF region->unrestricted( ) = abap_true OR request-members IS INITIAL.
      RETURN.
    ENDIF.
    result = answer( rows = rows_of( request = request list_members = abap_false ) request = request ).
  ENDMETHOD.

  METHOD rows_of.
    DATA(statement) = check_statement( profile = profile request = request list_members = list_members ).
    result = zzxxmla1_cl_sql=>query( sql = statement-sql columns = 6 params = statement-params ).
  ENDMETHOD.

  METHOD masks.
    IF region->provider_refusal( ) IS NOT INITIAL OR region->unrestricted( ) = abap_true.
      RETURN.
    ENDIF.
    DATA(request) = request( characteristics = profile-characteristics members = members ).
    IF request-members IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT rows_of( request = request list_members = abap_true ) INTO DATA(row).
      DATA(type) = condense( row[ 1 ] ).
      IF type = c_row-class.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( member = request-members[ CONV i( row[ 4 ] ) ]-member
                      mask   = COND #( WHEN type = c_row-member THEN CONV int8( row[ 3 ] ) )
                      reason = COND #( WHEN type = c_row-refused THEN condense( row[ 6 ] ) ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD answer.
    TYPES: BEGIN OF ty_refused,
             aggregate TYPE abap_bool,
             named     TYPE abap_bool,
             number    TYPE i,
             reason    TYPE string,
           END OF ty_refused.
    DATA refused TYPE STANDARD TABLE OF ty_refused WITH EMPTY KEY.
    DATA dimensions TYPE ty_dimensions.
    DATA mask TYPE ty_mask.
    result-status = zzxxmla1_cl_bw_auth=>c_status-allowed.
    LOOP AT rows INTO DATA(row).
      DATA(number) = CONV i( row[ 4 ] ).
      CASE condense( row[ 1 ] ).
        WHEN c_row-refused.
          DATA(member) = request-members[ number ]-member.
          DATA(aggregate) = xsdbool( member-kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate ).
          " an aggregate counts only in the product, where the query aggregates its characteristic
          IF aggregate = abap_true AND request-product = abap_false.
            CONTINUE.
          ENDIF.
          APPEND VALUE #( aggregate = aggregate named = member-named number = number reason = condense( row[ 6 ] ) )
            TO refused.
        WHEN c_row-class.
          DATA(pos) = CONV i( row[ 2 ] ).
          WHILE lines( dimensions ) < pos.
            APPEND INITIAL LINE TO dimensions.
          ENDWHILE.
          mask = CONV int8( row[ 3 ] ).
          ASSIGN dimensions[ pos ] TO FIELD-SYMBOL(<classes>).
          APPEND mask TO <classes>.
      ENDCASE.
    ENDLOOP.

    " BW checks the members before their combinations, the aggregates with the combinations
    IF refused IS NOT INITIAL.
      SORT refused BY aggregate ASCENDING named DESCENDING number ASCENDING.
      DATA(first) = refused[ 1 ].
      result = zzxxmla1_cl_bw_auth=>refusal(
                 reason = first-reason
                 member = COND #( WHEN first-aggregate = abap_false THEN request-members[ first-number ]-member ) ).
      RETURN.
    ENDIF.
    IF request-product = abap_false.
      RETURN.
    ENDIF.
    DELETE dimensions WHERE table_line IS INITIAL.
    IF dimensions IS NOT INITIAL AND hole( dimensions = dimensions depth = 1 mask = c_every ) = abap_true.
      result = zzxxmla1_cl_bw_auth=>refusal( reason = zzxxmla1_cl_bw_auth=>c_reason-combination member = VALUE #( ) ).
    ENDIF.
  ENDMETHOD.

  METHOD hole.
    DATA common TYPE ty_mask.
    DATA(classes) = dimensions[ depth ].
    LOOP AT classes INTO DATA(class).
      common = mask BIT-AND class.
      IF common IS INITIAL.
        result = abap_true.
        RETURN.
      ENDIF.
      IF depth < lines( dimensions ) AND hole( dimensions = dimensions depth = depth + 1 mask = common ) = abap_true.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD request.
    " the members in the order the query's tuples show them first, as ZZXXMLA1_CL_BW_AUTH's check meets them in the
    " product (the last factor fastest): tuple j of factor i first in the combination of the first tuples but j, whose
    " rank is (j - 1) times the number of combinations of the factors after i; then the members given alone
    TYPES: BEGIN OF ty_seen,
             rank     TYPE decfloat34,
             factor   TYPE i,
             position TYPE i,
             member   TYPE zzxxmla1_cl_bw_auth=>ty_member,
           END OF ty_seen.
    DATA seen TYPE STANDARD TABLE OF ty_seen WITH EMPTY KEY.
    result-product = xsdbool( factors IS NOT INITIAL ).
    LOOP AT factors INTO DATA(factor).
      DATA(i) = sy-tabix.
      IF factor IS INITIAL.
        " a factor without tuple: the query shows nothing, there is no product to check
        result-product = abap_false.
      ENDIF.
      DATA(after) = CONV decfloat34( 1 ).
      LOOP AT factors INTO DATA(later) FROM i + 1.
        after = after * lines( later ).
      ENDLOOP.
      LOOP AT factor INTO DATA(tuple).
        DATA(rank) = ( sy-tabix - 1 ) * after.
        LOOP AT tuple INTO DATA(member).
          APPEND VALUE #( rank = rank factor = i position = sy-tabix member = member ) TO seen.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
    SORT seen BY rank factor position.
    DATA(shown) = lines( seen ).
    DATA(all) = VALUE zzxxmla1_cl_bw_auth=>ty_tuple( FOR s IN seen ( s-member ) ).
    APPEND LINES OF members TO all.

    LOOP AT all INTO member.
      DATA(index) = sy-tabix.
      DATA(pos) = line_index( characteristics[ table_line = member-iobjnm ] ).
      IF pos = 0.
        CONTINUE.
      ENDIF.
      " a member a tuple shows is in the product, one the query only names is checked alone
      IF result-product = abap_false OR index > shown.
        pos = 0.
      ENDIF.
      READ TABLE result-members ASSIGNING FIELD-SYMBOL(<entry>) WITH KEY member = member.
      IF sy-subrc <> 0.
        APPEND VALUE #( member = member
                        key    = COND #( WHEN member-kind = zzxxmla1_cl_bw_auth=>c_kind-value AND member-value = `#`
                                         THEN `` ELSE member-value ) ) TO result-members ASSIGNING <entry>.
      ENDIF.
      IF <entry>-pos = 0.
        <entry>-pos = pos.
      ENDIF.
    ENDLOOP.

    " a characteristic the product has no member of is aggregated
    IF result-product = abap_true.
      LOOP AT characteristics INTO DATA(characteristic).
        pos = sy-tabix.
        IF NOT line_exists( result-members[ pos = pos ] ).
          APPEND VALUE #( member = VALUE #( iobjnm = characteristic kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate )
                          pos    = pos ) TO result-members.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD characteristics.
    result = region->profile( )-characteristics.
  ENDMETHOD.

  METHOD unrestricted.
    result = region->unrestricted( ).
  ENDMETHOD.

  METHOD provider_refusal.
    result = region->provider_refusal( ).
  ENDMETHOD.

  METHOD check_statement.
    DATA params TYPE zzxxmla1_cl_sql=>ty_t_param.
    DATA(sql) = VALUE string_table( ( `WITH` ) ).
    APPEND LINES OF inputs_sql( EXPORTING profile = profile request = request CHANGING params = params ) TO sql.
    APPEND LINES OF copies_sql( profile-tables ) TO sql.
    APPEND LINES OF check_sql( ) TO sql.
    " whether the members are listed with their masks: a bound value, so the text stays the same
    APPEND NEW i( COND #( WHEN list_members = abap_true THEN 1 ELSE 0 ) ) TO params.
    result = VALUE #( sql = concat_lines_of( table = sql sep = |\n| ) params = params ).
  ENDMETHOD.

  METHOD inputs_sql.
    DATA rows TYPE ty_rows.
    DATA(name) = `NVARCHAR(30)`.
    DATA(text) = `NVARCHAR(250)`.
    DATA(int) = `INTEGER`.

    " the authorizations of the profile, a bit each
    DATA(auths) = VALUE zzxxmla1_cl_bw_auth=>ty_auths( FOR f IN profile-flats ( f-auth ) ).
    APPEND LINES OF VALUE zzxxmla1_cl_bw_auth=>ty_auths( FOR l IN profile-lines ( l-line-auth ) ) TO auths.
    SORT auths BY table_line.
    DELETE ADJACENT DUPLICATES FROM auths COMPARING table_line.
    IF lines( auths ) > c_max_auths.
      RAISE EXCEPTION TYPE zzxxmla1_cx_sql
        EXPORTING
          statement     = ``
          error_message = |olap4abap checks at most { c_max_auths } analysis authorizations per user and provider, | &&
                          |{ lines( auths ) } apply|.
    ENDIF.

    APPEND `-- 1. Inputs, bound as JSON (the text never depends on them)` TO result.
    APPEND `-- the members of the query, per authorization-relevant characteristic (POS; 0: checked alone,` &&
           ` outside the product); KIND: V a flat value, N a node or leaf of a BW hierarchy, A the aggregate (:)`
      TO result.
    LOOP AT request-members INTO DATA(entry).
      APPEND VALUE #( ( NEW i( sy-tabix ) ) ( NEW i( entry-pos ) ) ( NEW string( entry-member-iobjnm ) )
                      ( NEW string( entry-member-kind ) ) ( NEW string( entry-key ) )
                      ( NEW string( entry-member-hienm ) ) ( NEW string( entry-member-version ) )
                      ( NEW string( entry-member-node_iobjnm ) )
                      ( NEW i( COND #( WHEN entry-member-named = abap_true THEN 1 ELSE 0 ) ) ) ) TO rows.
    ENDLOOP.
    APPEND |request_members AS (\n{ values_sql(
      EXPORTING columns = VALUE #( ( name = `M` type = int ) ( name = `POS` type = int ) ( name = `IOBJ` type = name )
                                   ( name = `KIND` type = `NVARCHAR(1)` ) ( name = `MEMBER_KEY` type = text )
                                   ( name = `HIENM` type = name ) ( name = `HIE_VERSION` type = name )
                                   ( name = `NODE_IOBJ` type = name ) ( name = `NAMED` type = int ) )
                rows    = rows
      CHANGING  params  = params ) } ),| TO result.

    APPEND `-- per applying authorization and characteristic: its bit and its flags` TO result.
    CLEAR rows.
    LOOP AT profile-flats INTO DATA(flat).
      DATA(bit) = CONV int8( 1 ).
      DATA(shift) = line_index( auths[ table_line = flat-auth ] ) - 1.
      DO shift TIMES.
        bit = bit * 2.
      ENDDO.
      APPEND VALUE #( ( NEW string( flat-auth ) ) ( NEW int8( bit ) ) ( NEW string( flat-iobjnm ) )
                      ( NEW i( COND #( WHEN flat-all = abap_true THEN 1 ELSE 0 ) ) )
                      ( NEW i( COND #( WHEN flat-aggregate = abap_true OR flat-all = abap_true THEN 1 ELSE 0 ) ) ) )
        TO rows.
    ENDLOOP.
    APPEND |auth_parts AS (\n{ values_sql(
      EXPORTING columns = VALUE #( ( name = `AUTH` type = name ) ( name = `AUTH_BIT` type = `BIGINT` )
                                   ( name = `IOBJ` type = name ) ( name = `ALL_VALUES` type = int )
                                   ( name = `AGGREGATE` type = int ) )
                rows    = rows
      CHANGING  params  = params ) } ),| TO result.

    APPEND `-- the flat ranges (CP as LIKE patterns; NUMC_PREFIX: the leading digits of a pattern, for NUMC keys)`
      TO result.
    CLEAR rows.
    LOOP AT profile-flats INTO flat WHERE all = abap_false.
      LOOP AT flat-ranges INTO DATA(range).
        DATA(pattern) = COND ty_like( WHEN range-option = 'CP' THEN like( range-low ) ).
        APPEND VALUE #( ( NEW string( flat-auth ) ) ( NEW string( flat-iobjnm ) ) ( NEW string( range-sign ) )
                        ( NEW string( range-option ) ) ( NEW string( range-low ) ) ( NEW string( range-high ) )
                        ( NEW string( pattern-pattern ) ) ( NEW string( pattern-number ) )
                        ( NEW string( pattern-rest ) ) ) TO rows.
      ENDLOOP.
    ENDLOOP.
    APPEND |auth_ranges AS (\n{ values_sql(
      EXPORTING columns = VALUE #( ( name = `AUTH` type = name ) ( name = `IOBJ` type = name )
                                   ( name = `SIGN` type = `NVARCHAR(1)` ) ( name = `OPT` type = `NVARCHAR(2)` )
                                   ( name = `LOW` type = text ) ( name = `HIGH` type = text )
                                   ( name = `LIKE_PATTERN` type = `NVARCHAR(500)` ) ( name = `NUMC_PREFIX` type = text )
                                   ( name = `NUMC_REST` type = `NVARCHAR(500)` ) )
                rows    = rows
      CHANGING  params  = params ) } ),| TO result.

    APPEND `-- the hierarchy lines, once per copy they read; COPY_ROLE: K the slice at the key date (the nodes it` &&
           ` shows), V the slice at the date of the line (the values it gives)` TO result.
    CLEAR rows.
    DATA copies TYPE ty_rows.
    DATA copy_keys TYPE string_table.
    LOOP AT profile-lines INTO DATA(line).
      " the key date's copy always (also without one: the line still names its hierarchy) but of an expired line, the
      " line date's if any
      DO 2 TIMES.
        DATA(role) = COND string( WHEN sy-index = 1 THEN c_key_copy ELSE c_value_copy ).
        DATA(copy) = COND ty_copy( WHEN sy-index = 1 THEN line-key_copy ELSE line-value_copy ).
        IF ( sy-index = 1 AND line-line-expired = abap_true ) OR ( sy-index = 2 AND copy-hiesid = 0 ).
          CONTINUE.
        ENDIF.
        APPEND VALUE #( ( NEW string( line-line-auth ) ) ( NEW string( line-line-iobjnm ) )
                        ( NEW string( line-line-hienm ) ) ( NEW string( line-line-version ) )
                        ( NEW string( line-line-node_iobjnm ) ) ( NEW string( line-line-node ) )
                        ( NEW string( line-line-type ) ) ( NEW i( line-line-level ) ) ( NEW string( role ) )
                        ( NEW i( copy-hiesid ) ) ( NEW string( copy-sver ) ) ) TO rows.
        DATA(copy_key) = |{ line-line-iobjnm } { copy-hiesid } { copy-sver }|.
        IF copy-hiesid <> 0 AND NOT line_exists( copy_keys[ table_line = copy_key ] ).
          APPEND copy_key TO copy_keys.
          APPEND VALUE #( ( NEW string( line-line-iobjnm ) ) ( NEW string( copy-basic ) ) ( NEW i( copy-hiesid ) )
                          ( NEW string( copy-sver ) )
                          ( NEW i( COND #( WHEN copy-rest_shown = abap_true THEN 1 ELSE 0 ) ) )
                          ( NEW i( copy-rest_top_sid ) ) ) TO copies.
        ENDIF.
      ENDDO.
    ENDLOOP.
    APPEND |auth_lines AS (\n{ values_sql(
      EXPORTING columns = VALUE #( ( name = `AUTH` type = name ) ( name = `IOBJ` type = name )
                                   ( name = `HIENM` type = name ) ( name = `HIE_VERSION` type = name )
                                   ( name = `NODE_IOBJ` type = name ) ( name = `NODE_NAME` type = text )
                                   ( name = `LINE_TYPE` type = `NVARCHAR(1)` ) ( name = `TO_LEVEL` type = int )
                                   ( name = `COPY_ROLE` type = `NVARCHAR(1)` ) ( name = `HIESID` type = int )
                                   ( name = `SVER` type = `NVARCHAR(10)` ) )
                rows    = rows
      CHANGING  params  = params ) } ),| TO result.

    APPEND `-- the copies the lines read, in the tables of their basic characteristic; REST_SHOWN: the copy shows` &&
           ` its not-assigned node REST_H (SID REST_TOP_SID)` TO result.
    APPEND |copies AS (\n{ values_sql(
      EXPORTING columns = VALUE #( ( name = `IOBJ` type = name ) ( name = `BASIC` type = name )
                                   ( name = `HIESID` type = int ) ( name = `SVER` type = `NVARCHAR(10)` )
                                   ( name = `REST_SHOWN` type = int ) ( name = `REST_TOP_SID` type = int ) )
                rows    = copies
      CHANGING  params  = params ) } ),| TO result.
  ENDMETHOD.

  METHOD copies_sql.
    DATA paths TYPE string_table.
    DATA values TYPE string_table.
    LOOP AT tables INTO DATA(table).
      DATA(basic) = zzxxmla1_cl_sql=>literal( condense( CONV string( table-basic ) ) ).
      APPEND |  SELECT c.IOBJ, p.HIESID, p.SVER, p.POS AS OCCURRENCE, p.TLEVEL, p.DEPTH, p.OWN_SID, p.NODE_IOBJ, | &&
             |p.NODE_NAME\n| &&
             |    FROM copies AS c\n| &&
             |    JOIN { zzxxmla1_cl_sql=>quote( table-path ) } AS p ON p.HIESID = c.HIESID AND p.SVER = c.SVER\n| &&
             |   WHERE c.BASIC = { basic }| TO paths.
      IF table-sid_table IS NOT INITIAL AND table-leaf_name IS NOT INITIAL.
        APPEND |  SELECT DISTINCT c.IOBJ, c.HIESID, c.SVER, { basic }, | &&
               |CASE WHEN r.SID = 0 THEN '' ELSE { table-leaf_name } END, 1\n| &&
               |    FROM copies AS c\n| &&
               |    JOIN { zzxxmla1_cl_sql=>quote( table-closure ) } AS r | &&
               |ON r.HIESID = c.HIESID AND r.SVER = c.SVER AND r.ANCESTOR_SID = c.REST_TOP_SID\n| &&
               |    JOIN { zzxxmla1_cl_sql=>quote( table-sid_table ) } AS s ON s.SID = r.SID\n| &&
               |   WHERE c.BASIC = { basic } AND c.REST_SHOWN = 1| TO values.
      ENDIF.
    ENDLOOP.
    IF paths IS INITIAL.
      " the provider has no hierarchy characteristic: no path rows
      APPEND |  SELECT c.IOBJ, c.HIESID, c.SVER, 0 AS OCCURRENCE, 0 AS TLEVEL, 0 AS DEPTH, 0 AS OWN_SID, | &&
             |c.IOBJ AS NODE_IOBJ, CAST( '' AS NVARCHAR(250) ) AS NODE_NAME\n| &&
             |    FROM copies AS c\n| &&
             |   WHERE 1 = 0| TO paths.
    ENDIF.

    DATA(union) = |\n  UNION ALL\n|.
    APPEND `-- 2. The rows of the copies (a branch per hierarchy characteristic of the provider)` TO result.
    APPEND `-- per occurrence of a member in a copy a row per level of its path (TLEVEL = DEPTH: the occurrence)`
      TO result.
    APPEND |copy_paths AS (\n{ concat_lines_of( table = paths sep = union ) } ),| TO result.
    APPEND `-- REST_H and the values below it, of the copies that show it (they have no path rows)` TO result.
    INSERT |  SELECT c.IOBJ, c.HIESID, c.SVER, | &&
           |CAST( '{ zzxxmla1_cl_bw_hierarchy_copy=>c_rest_iobj }' AS NVARCHAR(30) ) AS NODE_IOBJ,\n| &&
           |         CAST( '{ zzxxmla1_cl_bw_hierarchy_copy=>c_rest_node_name }' AS NVARCHAR(250) ) AS NODE_NAME, | &&
           |0 AS IS_LEAF\n| &&
           |    FROM copies AS c\n| &&
           |   WHERE c.REST_SHOWN = 1| INTO values INDEX 1.
    APPEND |copy_unassigned AS (\n{ concat_lines_of( table = values sep = union ) } ),| TO result.
  ENDMETHOD.

  METHOD check_sql.
    result = VALUE #(
      ( `-- 3. What each hierarchy line shows` )
      ( `-- the occurrences a line reaches, by a row of their path: type 0 the node itself, 1 its subtree, 2 its` &&
        ` subtree down to TO_LEVEL, 3 and 4 the complete hierarchy (the roots)` )
      ( `line_reach AS (` )
      ( `  SELECT l.AUTH, l.IOBJ, l.HIENM, l.HIE_VERSION, l.COPY_ROLE, p.HIESID, p.SVER, p.OCCURRENCE` )
      ( `    FROM auth_lines AS l` )
      ( `    JOIN copy_paths AS p ON p.IOBJ = l.IOBJ AND p.HIESID = l.HIESID AND p.SVER = l.SVER` )
      ( `   WHERE ( l.LINE_TYPE IN ( '3', '4' ) AND p.TLEVEL = 1 )` )
      ( `      OR ( l.LINE_TYPE NOT IN ( '3', '4' )` )
      ( `           AND p.NODE_IOBJ = l.NODE_IOBJ AND p.NODE_NAME = l.NODE_NAME` )
      ( `           AND ( l.LINE_TYPE <> '0' OR p.TLEVEL = p.DEPTH )` )
      ( `           AND ( l.LINE_TYPE <> '2' OR p.DEPTH <= l.TO_LEVEL OR p.TLEVEL = p.DEPTH ) ) ),` )
      ( `-- per line the members it shows, by name and InfoObject; IS_LEAF: a value it gives` )
      ( `line_members AS (` )
      ( `  SELECT DISTINCT r.AUTH, r.IOBJ, r.HIENM, r.HIE_VERSION, r.COPY_ROLE, o.NODE_IOBJ, o.NODE_NAME,` )
      ( `         CASE WHEN o.OWN_SID >= 0 THEN 1 ELSE 0 END AS IS_LEAF` )
      ( `    FROM line_reach AS r` )
      ( `    JOIN copy_paths AS o ON o.IOBJ = r.IOBJ AND o.HIESID = r.HIESID AND o.SVER = r.SVER` )
      ( `                        AND o.OCCURRENCE = r.OCCURRENCE AND o.TLEVEL = o.DEPTH` )
      ( `  UNION ALL` )
      ( `  SELECT DISTINCT l.AUTH, l.IOBJ, l.HIENM, l.HIE_VERSION, l.COPY_ROLE, u.NODE_IOBJ, u.NODE_NAME, u.IS_LEAF` )
      ( `    FROM auth_lines AS l` )
      ( `    JOIN copy_unassigned AS u ON u.IOBJ = l.IOBJ AND u.HIESID = l.HIESID AND u.SVER = l.SVER` )
      ( `   WHERE l.LINE_TYPE IN ( '3', '4' ) AND l.COPY_ROLE = 'K' ),` )

      ( `-- 4. Which authorizations admit each member` )
      ( `-- every flat range a value falls in (EQ, BT, CP; CP on a NUMC key also by the leading digits of the` &&
        ` pattern as a number)` )
      ( `range_matches AS (` )
      ( `  SELECT m.M, f.AUTH, f.SIGN` )
      ( `    FROM request_members AS m` )
      ( `    JOIN auth_ranges     AS f ON f.IOBJ = m.IOBJ` )
      ( `   WHERE m.KIND = 'V'` )
      ( `     AND (    ( f.OPT = 'EQ' AND m.MEMBER_KEY = f.LOW )` )
      ( `           OR ( f.OPT = 'BT' AND m.MEMBER_KEY >= f.LOW AND m.MEMBER_KEY <= f.HIGH )` )
      ( `           OR ( f.OPT = 'CP' AND m.MEMBER_KEY LIKE f.LIKE_PATTERN ESCAPE '\' )` )
      ( `           OR ( f.OPT = 'CP' AND f.NUMC_PREFIX <> ''` )
      ( `                AND LENGTH( m.MEMBER_KEY ) > LENGTH( f.NUMC_PREFIX )` )
      ( `                AND m.MEMBER_KEY LIKE_REGEXPR '^[0-9]+$'` )
      ( `                AND m.MEMBER_KEY LIKE LPAD( f.NUMC_PREFIX, LENGTH( m.MEMBER_KEY ), '0' ) || f.NUMC_REST` &&
        ` ESCAPE '\' ) ) ),` )
      ( `-- a value: in an including range or among the values of a line, and in no excluding range` )
      ( `value_admissions AS (` )
      ( `  ( SELECT M, AUTH FROM range_matches WHERE SIGN = 'I'` )
      ( `    UNION` )
      ( `    SELECT m.M, l.AUTH` )
      ( `      FROM request_members AS m` )
      ( `      JOIN line_members    AS l ON l.IOBJ = m.IOBJ AND l.COPY_ROLE = 'V' AND l.IS_LEAF = 1` )
      ( `                               AND l.NODE_NAME = m.MEMBER_KEY` )
      ( `     WHERE m.KIND = 'V' )` )
      ( `  EXCEPT` )
      ( `  SELECT M, AUTH FROM range_matches WHERE SIGN = 'E' ),` )
      ( `-- a node or leaf of a hierarchy: shown by a line on that hierarchy in the copy of the key date` )
      ( `node_admissions AS (` )
      ( `  SELECT m.M, l.AUTH` )
      ( `    FROM request_members AS m` )
      ( `    JOIN line_members    AS l ON l.IOBJ = m.IOBJ AND l.COPY_ROLE = 'K'` )
      ( `                             AND l.HIENM = m.HIENM AND l.HIE_VERSION = m.HIE_VERSION` )
      ( `                             AND l.NODE_IOBJ = m.NODE_IOBJ AND l.NODE_NAME = m.MEMBER_KEY` )
      ( `   WHERE m.KIND = 'N' ),` )
      ( `-- any member: all values (*); the aggregate: the flag for :` )
      ( `flag_admissions AS (` )
      ( `  SELECT m.M, p.AUTH` )
      ( `    FROM request_members AS m` )
      ( `    JOIN auth_parts      AS p ON p.IOBJ = m.IOBJ` )
      ( `   WHERE p.ALL_VALUES = 1 OR ( m.KIND = 'A' AND p.AGGREGATE = 1 ) ),` )
      ( `-- per member the authorizations that admit it, with their bits` )
      ( `member_admissions AS (` )
      ( `  SELECT DISTINCT a.M, a.AUTH, p.AUTH_BIT` )
      ( `    FROM ( SELECT M, AUTH FROM value_admissions` )
      ( `           UNION ALL SELECT M, AUTH FROM node_admissions` )
      ( `           UNION ALL SELECT M, AUTH FROM flag_admissions ) AS a` )
      ( `    JOIN request_members AS m ON m.M = a.M` )
      ( `    JOIN auth_parts      AS p ON p.AUTH = a.AUTH AND p.IOBJ = m.IOBJ ),` )

      ( `-- 5. Masks and classes` )
      ( `-- per member the OR of the bits of the authorizations that admit it (each once, so SUM is the OR); 0: none` )
      ( `member_masks AS (` )
      ( `  SELECT m.M, m.POS, m.IOBJ, m.KIND, m.NAMED, m.HIENM, m.HIE_VERSION,` )
      ( `         COALESCE( SUM( a.AUTH_BIT ), 0 ) AS MASK` )
      ( `    FROM request_members        AS m` )
      ( `    LEFT JOIN member_admissions AS a ON a.M = m.M` )
      ( `   GROUP BY m.M, m.POS, m.IOBJ, m.KIND, m.NAMED, m.HIENM, m.HIE_VERSION ),` )
      ( `-- per characteristic of the product its members with one mask: interchangeable in every combination` )
      ( `member_classes AS (` )
      ( `  SELECT POS, MASK, MIN( M ) AS FIRST_M, COUNT(*) AS MEMBER_COUNT` )
      ( `    FROM member_masks` )
      ( `   WHERE MASK <> 0 AND POS > 0` )
      ( `   GROUP BY POS, MASK ),` )

      ( `-- 6. Why a member is refused (the reasons of BW)` )
      ( `-- the characteristics the user has any value of` )
      ( `characteristics_with_values AS (` )
      ( `  SELECT IOBJ FROM auth_parts WHERE ALL_VALUES = 1` )
      ( `  UNION SELECT IOBJ FROM auth_ranges` )
      ( `  UNION SELECT IOBJ FROM line_members WHERE COPY_ROLE = 'V' AND IS_LEAF = 1 ),` )
      ( `-- the hierarchies the user has a line on at the key date (with a copy, or without a slice at the date)` )
      ( `hierarchies_with_lines AS (` )
      ( `  SELECT IOBJ, HIENM, HIE_VERSION FROM line_members WHERE COPY_ROLE = 'K'` )
      ( `  UNION SELECT IOBJ, HIENM, HIE_VERSION FROM auth_lines WHERE COPY_ROLE = 'K' AND HIESID = 0 ),` )
      ( `refused_members AS (` )
      ( `  SELECT k.M, k.POS,` )
      ( |         CASE WHEN k.KIND = 'A'                    THEN '{ zzxxmla1_cl_bw_auth=>c_reason-combination }'| )
      ( |              WHEN k.KIND = 'V' AND v.IOBJ IS NULL THEN '{ zzxxmla1_cl_bw_auth=>c_reason-no_values }'| )
      ( |              WHEN k.KIND = 'V' AND k.NAMED = 1    THEN '{ zzxxmla1_cl_bw_auth=>c_reason-value }'| )
      ( |              WHEN k.KIND = 'V'                    THEN '{ zzxxmla1_cl_bw_auth=>c_reason-combination }'| )
      ( |              WHEN h.IOBJ IS NOT NULL              THEN '{ zzxxmla1_cl_bw_auth=>c_reason-node }'| )
      ( |              ELSE                                      '{ zzxxmla1_cl_bw_auth=>c_reason-hierarchy }' | &&
        |END AS REASON| )
      ( `    FROM member_masks                     AS k` )
      ( `    LEFT JOIN characteristics_with_values AS v ON v.IOBJ = k.IOBJ` )
      ( `    LEFT JOIN hierarchies_with_lines      AS h ON h.IOBJ = k.IOBJ AND h.HIENM = k.HIENM` )
      ( `                                              AND h.HIE_VERSION = k.HIE_VERSION` )
      ( `   WHERE k.MASK = 0 )` )

      ( `-- The answer: the classes (their combinations are searched in ABAP), on request the members with their` &&
        ` masks, and the refused members` )
      ( `SELECT CAST( 'CLASS' AS NVARCHAR(10) ) AS ROW_TYPE, POS, MASK, FIRST_M AS M, MEMBER_COUNT,` &&
        ` CAST( NULL AS NVARCHAR(12) ) AS REASON` )
      ( `  FROM member_classes` )
      ( `UNION ALL` )
      ( `SELECT 'MEMBER', POS, MASK, M, 1, NULL` )
      ( `  FROM member_masks` )
      ( ` WHERE MASK <> 0 AND CAST( ? AS INTEGER ) = 1` )
      ( `UNION ALL` )
      ( `SELECT 'REFUSED', POS, 0, M, 1, REASON` )
      ( `  FROM refused_members` )
      ( `ORDER BY ROW_TYPE, POS, M` ) ).
  ENDMETHOD.

  METHOD values_sql.
    DATA definitions TYPE string_table.
    LOOP AT columns INTO DATA(column).
      APPEND |    { column-name } { column-type } PATH '$.{ column-name }'| TO definitions.
    ENDLOOP.
    APPEND NEW string( values_json( columns = columns rows = rows ) ) TO params.
    DATA(separator) = |,\n|.
    result = |  SELECT * FROM JSON_TABLE( CAST( ? AS NCLOB ), '$[*]' COLUMNS (\n| &&
             |{ concat_lines_of( table = definitions sep = separator ) } ) ) AS j|.
  ENDMETHOD.

  METHOD values_json.
    DATA objects TYPE string_table.
    DATA pairs TYPE string_table.
    FIELD-SYMBOLS <value> TYPE any.
    LOOP AT rows INTO DATA(row).
      CLEAR pairs.
      LOOP AT row INTO DATA(param).
        DATA(name) = columns[ sy-tabix ]-name.
        ASSIGN param->* TO <value>.
        DESCRIBE FIELD <value> TYPE DATA(kind).
        IF kind = cl_abap_typedescr=>typekind_int OR kind = cl_abap_typedescr=>typekind_int8.
          " a template, not CONV string, which keeps the sign position as a trailing blank
          APPEND |"{ name }":{ <value> }| TO pairs.
        ELSE.
          APPEND |"{ name }":"{ escape( val = CONV string( <value> ) format = cl_abap_format=>e_json_string ) }"|
            TO pairs.
        ENDIF.
      ENDLOOP.
      APPEND |\{{ concat_lines_of( table = pairs sep = `,` ) }\}| TO objects.
    ENDLOOP.
    result = |[{ concat_lines_of( table = objects sep = `,` ) }]|.
  ENDMETHOD.

  METHOD like.
    result-pattern = like_pattern( pattern ).
    DATA(digits) = find( val = pattern regex = `[^0-9]` ).
    IF digits > 0.
      result-number = substring( val = pattern len = digits ).
      result-rest = like_pattern( substring( val = pattern off = digits ) ).
    ENDIF.
  ENDMETHOD.

  METHOD like_pattern.
    DATA(offset) = 0.
    WHILE offset < strlen( pattern ).
      DATA(char) = substring( val = pattern off = offset len = 1 ).
      result = result && SWITCH string( char
                                        WHEN `*` THEN `%`
                                        WHEN `+` THEN `_`
                                        WHEN `%` OR `_` OR `\` THEN `\` && char
                                        ELSE char ).
      offset = offset + 1.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.
