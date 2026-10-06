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
"! The type of an MDX expression: the port of olap.type (BooleanType, NumericType, DecimalType, StringType,
"! DateTimeType, SymbolType, NullType, EmptyType, ScalarType, MemberType, TupleType, SetType, LevelType, HierarchyType,
"! DimensionType, CubeType) and of the TypeUtil methods on types. The OLAP elements a type knows are the ids of
"! ZZXXMLA1_CL_MDX_SCHEMA_READER: dimension and hierarchy (0 is Measures, -1 is none), level (0 is none) and the unique
"! name of a member. Categories are the numbers of olap.Category.
CLASS zzxxmla1_cl_mdx_type DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES ty_t_type TYPE STANDARD TABLE OF REF TO zzxxmla1_cl_mdx_type WITH EMPTY KEY.
    CONSTANTS:
      BEGIN OF c_kind,
        boolean   TYPE string VALUE `Boolean`,
        numeric   TYPE string VALUE `Numeric`,
        decimal   TYPE string VALUE `Decimal`,
        string    TYPE string VALUE `String`,
        datetime  TYPE string VALUE `DateTime`,
        symbol    TYPE string VALUE `Symbol`,
        null      TYPE string VALUE `Null`,
        empty     TYPE string VALUE `Empty`,
        scalar    TYPE string VALUE `Scalar`,
        member    TYPE string VALUE `Member`,
        tuple     TYPE string VALUE `Tuple`,
        set       TYPE string VALUE `Set`,
        level     TYPE string VALUE `Level`,
        hierarchy TYPE string VALUE `Hierarchy`,
        dimension TYPE string VALUE `Dimension`,
        cube      TYPE string VALUE `Cube`,
      END OF c_kind,
      BEGIN OF c_category,
        unknown   TYPE i VALUE 0,
        array     TYPE i VALUE 1,
        dimension TYPE i VALUE 2,
        hierarchy TYPE i VALUE 3,
        level     TYPE i VALUE 4,
        logical   TYPE i VALUE 5,
        member    TYPE i VALUE 6,
        numeric   TYPE i VALUE 7,
        set       TYPE i VALUE 8,
        string    TYPE i VALUE 9,
        tuple     TYPE i VALUE 10,
        symbol    TYPE i VALUE 11,
        cube      TYPE i VALUE 12,
        value     TYPE i VALUE 13,
        integer   TYPE i VALUE 15,
        null      TYPE i VALUE 16,
        empty     TYPE i VALUE 17,
        datetime  TYPE i VALUE 18,
        constant  TYPE i VALUE 64,
        mask      TYPE i VALUE 31,
      END OF c_category.
    CONSTANTS c_none TYPE i VALUE -1.

    DATA kind          TYPE string READ-ONLY.
    DATA dimension     TYPE i READ-ONLY VALUE -1.
    DATA hierarchy     TYPE i READ-ONLY VALUE -1.
    DATA level         TYPE i READ-ONLY.
    DATA member        TYPE string READ-ONLY.          " unique name of the member of a MemberType
    DATA element_type  TYPE REF TO zzxxmla1_cl_mdx_type READ-ONLY.  " SetType
    DATA element_types TYPE ty_t_type READ-ONLY.       " TupleType
    DATA scale         TYPE i READ-ONLY.               " DecimalType

    CLASS-METHODS boolean RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS numeric RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS decimal
      IMPORTING scale         TYPE i
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS string RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS datetime RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS symbol RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS null RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS empty RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS scalar RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS cube RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    "! MemberType(dimension, hierarchy, level, member); MemberType.Unknown has none of them.
    CLASS-METHODS member_type
      IMPORTING dimension     TYPE i DEFAULT c_none
                hierarchy     TYPE i DEFAULT c_none
                level         TYPE i DEFAULT 0
                member        TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS tuple_type
      IMPORTING element_types TYPE ty_t_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    "! SetType(elementType); the element is a member or a tuple type, or none.
    CLASS-METHODS set_type
      IMPORTING element_type  TYPE REF TO zzxxmla1_cl_mdx_type OPTIONAL
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS level_type
      IMPORTING dimension     TYPE i
                hierarchy     TYPE i
                level         TYPE i
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS hierarchy_type
      IMPORTING dimension     TYPE i
                hierarchy     TYPE i
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    "! @parameter hierarchy | DimensionType.getHierarchy: the dimension's only hierarchy, or the one named like it
    "! (ZZXXMLA1_CL_MDX_SCHEMA_READER=>GET_DIMENSION_HIERARCHY)
    CLASS-METHODS dimension_type
      IMPORTING dimension     TYPE i
                hierarchy     TYPE i DEFAULT c_none
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    "! The forType methods: MemberType.forType, LevelType.forType, HierarchyType.forType, DimensionType.forType.
    CLASS-METHODS member_for_type
      IMPORTING type          TYPE REF TO zzxxmla1_cl_mdx_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS level_for_type
      IMPORTING type          TYPE REF TO zzxxmla1_cl_mdx_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    CLASS-METHODS hierarchy_for_type
      IMPORTING type          TYPE REF TO zzxxmla1_cl_mdx_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    "! @parameter hierarchy | the hierarchy of the type's dimension (dimension_type)
    CLASS-METHODS dimension_for_type
      IMPORTING type          TYPE REF TO zzxxmla1_cl_mdx_type
                hierarchy     TYPE i DEFAULT c_none
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    "! Category.getDescription: Member, Numeric Expression, Logical Expression, ...
    CLASS-METHODS category_description
      IMPORTING category      TYPE i
      RETURNING VALUE(result) TYPE string.

    "! TypeUtil.typeToCategory.
    METHODS category RETURNING VALUE(result) TYPE i.
    "! Type.getDimension, getHierarchy, getLevel; a tuple has none (the reference throws).
    METHODS get_dimension RETURNING VALUE(result) TYPE i.
    METHODS get_hierarchy RETURNING VALUE(result) TYPE i.
    METHODS get_level RETURNING VALUE(result) TYPE i.
    "! Type.usesHierarchy; dimension_of_hierarchy is the dimension of the hierarchy asked for.
    METHODS uses_hierarchy
      IMPORTING hierarchy              TYPE i
                dimension_of_hierarchy TYPE i
                definitely             TYPE abap_bool
      RETURNING VALUE(result)          TYPE abap_bool.
    METHODS get_arity RETURNING VALUE(result) TYPE i.
    "! TypeUtil.isSet, canEvaluate, stripSetType, toMemberType, toMemberOrTupleType, isUnionCompatible.
    METHODS is_set RETURNING VALUE(result) TYPE abap_bool.
    METHODS can_evaluate RETURNING VALUE(result) TYPE abap_bool.
    METHODS strip_set_type RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    "! A tuple of arity 1 becomes the member type of its hierarchy: dimension_of is the dimension of that hierarchy.
    METHODS to_member_type
      IMPORTING dimension_of  TYPE i DEFAULT c_none
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    METHODS to_member_or_tuple_type
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
    METHODS is_union_compatible
      IMPORTING other         TYPE REF TO zzxxmla1_cl_mdx_type
      RETURNING VALUE(result) TYPE abap_bool.
    "! The type as toString writes it, with ids instead of names (for tests).
    METHODS describe RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS create
      IMPORTING kind          TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_type.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_type IMPLEMENTATION.

  METHOD create.
    result = NEW #( ).
    result->kind = kind.
  ENDMETHOD.

  METHOD boolean.
    result = create( c_kind-boolean ).
  ENDMETHOD.

  METHOD numeric.
    result = create( c_kind-numeric ).
  ENDMETHOD.

  METHOD decimal.
    result = create( c_kind-decimal ).
    result->scale = scale.
  ENDMETHOD.

  METHOD string.
    result = create( c_kind-string ).
  ENDMETHOD.

  METHOD datetime.
    result = create( c_kind-datetime ).
  ENDMETHOD.

  METHOD symbol.
    result = create( c_kind-symbol ).
  ENDMETHOD.

  METHOD null.
    result = create( c_kind-null ).
  ENDMETHOD.

  METHOD empty.
    result = create( c_kind-empty ).
  ENDMETHOD.

  METHOD scalar.
    result = create( c_kind-scalar ).
  ENDMETHOD.

  METHOD cube.
    result = create( c_kind-cube ).
  ENDMETHOD.

  METHOD member_type.
    result = create( c_kind-member ).
    result->dimension = dimension.
    result->hierarchy = hierarchy.
    result->level = level.
    result->member = member.
  ENDMETHOD.

  METHOD tuple_type.
    result = create( c_kind-tuple ).
    result->element_types = element_types.
  ENDMETHOD.

  METHOD set_type.
    result = create( c_kind-set ).
    result->element_type = element_type.
  ENDMETHOD.

  METHOD level_type.
    result = create( c_kind-level ).
    result->dimension = dimension.
    result->hierarchy = hierarchy.
    result->level = level.
  ENDMETHOD.

  METHOD hierarchy_type.
    result = create( c_kind-hierarchy ).
    result->dimension = dimension.
    result->hierarchy = hierarchy.
  ENDMETHOD.

  METHOD dimension_type.
    result = create( c_kind-dimension ).
    result->dimension = dimension.
    result->hierarchy = hierarchy.
  ENDMETHOD.

  METHOD member_for_type.
    IF type->kind = c_kind-member.
      result = type.
    ELSE.
      result = member_type( dimension = type->get_dimension( ) hierarchy = type->get_hierarchy( )
                            level = type->get_level( ) ).
    ENDIF.
  ENDMETHOD.

  METHOD level_for_type.
    result = level_type( dimension = type->get_dimension( ) hierarchy = type->get_hierarchy( ) level = type->get_level( ) ).
  ENDMETHOD.

  METHOD hierarchy_for_type.
    result = hierarchy_type( dimension = type->get_dimension( ) hierarchy = type->get_hierarchy( ) ).
  ENDMETHOD.

  METHOD dimension_for_type.
    result = dimension_type( dimension = type->get_dimension( ) hierarchy = hierarchy ).
  ENDMETHOD.

  METHOD category_description.
    " category & Category.Mask: the low five bits, without the Constant flag (64)
    result = SWITCH #( category MOD 32
                       WHEN 0 THEN `Unknown` WHEN 1 THEN `Array` WHEN 2 THEN `Dimension` WHEN 3 THEN `Hierarchy`
                       WHEN 4 THEN `Level` WHEN 5 THEN `Logical Expression` WHEN 6 THEN `Member`
                       WHEN 7 THEN `Numeric Expression` WHEN 8 THEN `Set` WHEN 9 THEN `String` WHEN 10 THEN `Tuple`
                       WHEN 11 THEN `Symbol` WHEN 12 THEN `Cube` WHEN 13 THEN `Value` WHEN 15 THEN `Integer`
                       WHEN 16 THEN `Null` WHEN 17 THEN `Empty` WHEN 18 THEN `DateTime` ).
  ENDMETHOD.

  METHOD category.
    result = SWITCH #( kind
                       WHEN c_kind-null THEN c_category-null
                       WHEN c_kind-empty THEN c_category-empty
                       WHEN c_kind-datetime THEN c_category-datetime
                       WHEN c_kind-decimal THEN COND #( WHEN scale = 0 THEN c_category-integer ELSE c_category-numeric )
                       WHEN c_kind-numeric THEN c_category-numeric
                       WHEN c_kind-boolean THEN c_category-logical
                       WHEN c_kind-dimension THEN c_category-dimension
                       WHEN c_kind-hierarchy THEN c_category-hierarchy
                       WHEN c_kind-member THEN c_category-member
                       WHEN c_kind-level THEN c_category-level
                       WHEN c_kind-symbol THEN c_category-symbol
                       WHEN c_kind-string THEN c_category-string
                       WHEN c_kind-scalar THEN c_category-value
                       WHEN c_kind-set THEN c_category-set
                       WHEN c_kind-tuple THEN c_category-tuple
                       WHEN c_kind-cube THEN c_category-cube ).
  ENDMETHOD.

  METHOD get_dimension.
    CASE kind.
      WHEN c_kind-set.
        result = COND #( WHEN element_type IS BOUND THEN element_type->get_dimension( ) ELSE c_none ).
      WHEN c_kind-member OR c_kind-level OR c_kind-hierarchy OR c_kind-dimension.
        result = dimension.
      WHEN OTHERS.
        result = c_none.
    ENDCASE.
  ENDMETHOD.

  METHOD get_hierarchy.
    CASE kind.
      WHEN c_kind-set.
        result = COND #( WHEN element_type IS BOUND THEN element_type->get_hierarchy( ) ELSE c_none ).
      WHEN c_kind-member OR c_kind-level OR c_kind-hierarchy OR c_kind-dimension.
        result = hierarchy.
      WHEN OTHERS.
        result = c_none.
    ENDCASE.
  ENDMETHOD.

  METHOD get_level.
    CASE kind.
      WHEN c_kind-set.
        result = COND #( WHEN element_type IS BOUND THEN element_type->get_level( ) ).
      WHEN c_kind-member OR c_kind-level.
        result = level.
    ENDCASE.
  ENDMETHOD.

  METHOD uses_hierarchy.
    CASE kind.
      WHEN c_kind-member OR c_kind-level OR c_kind-hierarchy.
        " MemberType: the hierarchy itself, or, not definitely, an unknown hierarchy of the same or no dimension
        result = xsdbool( me->hierarchy = hierarchy
                          OR ( definitely = abap_false AND me->hierarchy = c_none
                               AND ( me->dimension = c_none OR me->dimension = dimension_of_hierarchy ) ) ).
      WHEN c_kind-dimension.
        result = xsdbool( me->dimension = dimension_of_hierarchy
                          OR ( definitely = abap_false AND me->dimension = c_none ) ).
      WHEN c_kind-tuple.
        LOOP AT element_types INTO DATA(element).
          IF element->uses_hierarchy( hierarchy = hierarchy dimension_of_hierarchy = dimension_of_hierarchy
                                      definitely = definitely ) = abap_true.
            result = abap_true.
            RETURN.
          ENDIF.
        ENDLOOP.
      WHEN c_kind-set.
        IF element_type IS NOT BOUND.
          result = definitely.
        ELSE.
          result = element_type->uses_hierarchy( hierarchy = hierarchy dimension_of_hierarchy = dimension_of_hierarchy
                                                 definitely = definitely ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD get_arity.
    result = SWITCH #( kind WHEN c_kind-tuple THEN lines( element_types )
                            WHEN c_kind-set THEN COND #( WHEN element_type IS BOUND THEN element_type->get_arity( ) ELSE 1 )
                            ELSE 1 ).
  ENDMETHOD.

  METHOD is_set.
    result = xsdbool( kind = c_kind-set ).
  ENDMETHOD.

  METHOD can_evaluate.
    result = xsdbool( NOT ( kind = c_kind-set OR kind = c_kind-cube OR kind = c_kind-level ) ).
  ENDMETHOD.

  METHOD strip_set_type.
    result = me.
    WHILE result IS BOUND AND result->kind = c_kind-set.
      result = result->element_type.
    ENDWHILE.
  ENDMETHOD.

  METHOD to_member_type.
    DATA(type) = strip_set_type( ).
    IF type IS NOT BOUND.
      RETURN.
    ENDIF.
    CASE type->kind.
      WHEN c_kind-member.
        result = type.
      WHEN c_kind-dimension OR c_kind-hierarchy OR c_kind-level.
        result = member_for_type( type ).
      WHEN c_kind-tuple.
        IF lines( type->element_types ) = 1.
          result = member_type( dimension = dimension_of hierarchy = type->element_types[ 1 ]->get_hierarchy( ) ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD to_member_or_tuple_type.
    DATA(type) = strip_set_type( ).
    IF type IS BOUND AND type->kind = c_kind-tuple.
      result = type.
    ELSEIF type IS BOUND.
      result = type->to_member_type( ).
    ENDIF.
  ENDMETHOD.

  METHOD is_union_compatible.
    DATA(member1) = to_member_type( ).
    DATA(member2) = other->to_member_type( ).
    IF member1 IS BOUND AND member2 IS BOUND.
      result = xsdbool( member1->hierarchy = member2->hierarchy ).
      RETURN.
    ENDIF.
    IF kind = c_kind-tuple AND other->kind = c_kind-tuple AND lines( element_types ) = lines( other->element_types ).
      LOOP AT element_types INTO DATA(element).
        IF element->is_union_compatible( other->element_types[ sy-tabix ] ) = abap_false.
          RETURN.
        ENDIF.
      ENDLOOP.
      result = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD describe.
    CASE kind.
      WHEN c_kind-member.
        result = |MemberType<{ COND #( WHEN member IS NOT INITIAL THEN |member={ member }|
                                       WHEN level > 0 THEN |level={ level }|
                                       WHEN hierarchy <> c_none THEN |hierarchy={ hierarchy }|
                                       WHEN dimension <> c_none THEN |dimension={ dimension }| ) }>|.
      WHEN c_kind-tuple.
        result = `TupleType<`.
        LOOP AT element_types INTO DATA(element).
          result = result && COND #( WHEN sy-tabix > 1 THEN `, ` ) && element->describe( ).
        ENDLOOP.
        result = result && `>`.
      WHEN c_kind-set.
        result = |SetType<{ COND #( WHEN element_type IS BOUND THEN element_type->describe( ) ELSE `null` ) }>|.
      WHEN c_kind-level.
        result = |LevelType<level={ level }>|.
      WHEN c_kind-hierarchy.
        result = |HierarchyType<hierarchy={ hierarchy }>|.
      WHEN c_kind-dimension.
        result = |DimensionType<dimension={ dimension }>|.
      WHEN OTHERS.
        result = |{ kind }Type|.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
