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
"! Rowsets of XML for Analysis that are the same for every cube: the answers of the reference for DISCOVER_ENUMERATORS,
"! DISCOVER_KEYWORDS, DISCOVER_LITERALS, DBSCHEMA_PROVIDER_TYPES and MDSCHEMA_FUNCTIONS, taken from the reference server. Static
"! knowledge of the engine, not read from the model tables. A row is a line of name=value pairs separated by ~; a
"! row can lack columns (an optional column is missing, not empty). MDSCHEMA_FUNCTIONS lists the functions of the reference,
"! also those this server's MDX engine does not have yet.
CLASS zzxxmla1_cl_xmla_static DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_row   TYPE zzxxmla1_cl_xmla_request=>ty_t_pair.
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    "! The rows of a rowset by its request type (DISCOVER_ENUMERATORS, DISCOVER_KEYWORDS, DISCOVER_LITERALS,
    "! DBSCHEMA_PROVIDER_TYPES, MDSCHEMA_FUNCTIONS); empty for another one.
    CLASS-METHODS get_rows
      IMPORTING rowset        TYPE string
      RETURNING VALUE(result) TYPE ty_t_row.

  PRIVATE SECTION.
    CLASS-METHODS enumerators RETURNING VALUE(result) TYPE string_table.
    CLASS-METHODS keywords RETURNING VALUE(result) TYPE string_table.
    CLASS-METHODS literals RETURNING VALUE(result) TYPE string_table.
    CLASS-METHODS provider_types RETURNING VALUE(result) TYPE string_table.
    CLASS-METHODS functions RETURNING VALUE(result) TYPE string_table.
ENDCLASS.

CLASS zzxxmla1_cl_xmla_static IMPLEMENTATION.
  METHOD get_rows.
    DATA(lines) = SWITCH string_table( rowset
      WHEN 'DISCOVER_ENUMERATORS' THEN enumerators( )
      WHEN 'DISCOVER_KEYWORDS' THEN keywords( )
      WHEN 'DISCOVER_LITERALS' THEN literals( )
      WHEN 'DBSCHEMA_PROVIDER_TYPES' THEN provider_types( )
      WHEN 'MDSCHEMA_FUNCTIONS' THEN functions( )
      ELSE VALUE #( ) ).
    LOOP AT lines INTO DATA(line).
      DATA(row) = VALUE ty_row( ).
      SPLIT line AT '~' INTO TABLE DATA(fields).
      LOOP AT fields INTO DATA(field).
        SPLIT field AT '=' INTO DATA(name) DATA(value).
        " a value can contain =: everything behind the first one is the value
        value = substring_after( val = field sub = '=' ).
        APPEND VALUE #( name = name value = value ) TO row.
      ENDLOOP.
      APPEND row TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD enumerators.
    APPEND `EnumName=Access~EnumDescription=The read/write behavior of a property~EnumType=string~ElementName=Read~ElementValue=1` TO result.
    APPEND `EnumName=Access~EnumDescription=The read/write behavior of a property~EnumType=string~ElementName=Write~ElementValue=2` TO result.
    APPEND `EnumName=Access~EnumDescription=The read/write behavior of a property~EnumType=string~ElementName=ReadWrite~ElementValue=3` TO result.
    APPEND `EnumName=AuthenticationMode~EnumDescription=Specification of what type of security mode the data source uses.~EnumType=string~ElementName=Unauthentica` &&
        `ted~ElementDescription=no user ID or password needs to be sent.~ElementValue=0` TO result.
    APPEND `EnumName=AuthenticationMode~EnumDescription=Specification of what type of security mode the data source uses.~EnumType=string~ElementName=Authenticate` &&
        `d~ElementDescription=User ID and Password must be included in the information required for the connection.~ElementValue=1` TO result.
    APPEND `EnumName=AuthenticationMode~EnumDescription=Specification of what type of security mode the data source uses.~EnumType=string~ElementName=Integrated~E` &&
        `lementDescription=the data source uses the underlying security to determine authorization, such as Integrated Security provided by Microsoft Internet ` &&
        `Information Services (IIS).~ElementValue=2` TO result.
    APPEND `EnumName=ProviderType~EnumDescription=The types of data supported by the provider.~EnumType=string~ElementName=TDP~ElementDescription=tabular data pro` &&
        `vider.~ElementValue=0` TO result.
    APPEND `EnumName=ProviderType~EnumDescription=The types of data supported by the provider.~EnumType=string~ElementName=MDP~ElementDescription=multidimensional` &&
        ` data provider.~ElementValue=1` TO result.
    APPEND `EnumName=ProviderType~EnumDescription=The types of data supported by the provider.~EnumType=string~ElementName=DMP~ElementDescription=data mining prov` &&
        `ider. A DMP provider implements the OLE DB for Data Mining specification.~ElementValue=2` TO result.
    APPEND `EnumName=TREE_OP~EnumDescription=Bitmap which controls which relatives of a member are returned~EnumType=string~ElementName=MDTREEOP_CHILDREN~ElementD` &&
        `escription=Tree operation which returns only the immediate children.~ElementValue=1` TO result.
    APPEND `EnumName=TREE_OP~EnumDescription=Bitmap which controls which relatives of a member are returned~EnumType=string~ElementName=MDTREEOP_SIBLINGS~ElementD` &&
        `escription=Tree operation which returns members on the same level.~ElementValue=2` TO result.
    APPEND `EnumName=TREE_OP~EnumDescription=Bitmap which controls which relatives of a member are returned~EnumType=string~ElementName=MDTREEOP_PARENT~ElementDes` &&
        `cription=Tree operation which returns only the immediate parent.~ElementValue=4` TO result.
    APPEND `EnumName=TREE_OP~EnumDescription=Bitmap which controls which relatives of a member are returned~EnumType=string~ElementName=MDTREEOP_SELF~ElementDescr` &&
        `iption=Tree operation which returns itself in the list of returned rows.~ElementValue=8` TO result.
    APPEND `EnumName=TREE_OP~EnumDescription=Bitmap which controls which relatives of a member are returned~EnumType=string~ElementName=MDTREEOP_DESCENDANTS~Eleme` &&
        `ntDescription=Tree operation which returns all of the descendants.~ElementValue=16` TO result.
    APPEND `EnumName=TREE_OP~EnumDescription=Bitmap which controls which relatives of a member are returned~EnumType=string~ElementName=MDTREEOP_ANCESTORS~Element` &&
        `Description=Tree operation which returns all of the ancestors.~ElementValue=32` TO result.
  ENDMETHOD.

  METHOD keywords.
    APPEND `Keyword=$AdjustedProbability` TO result.
    APPEND `Keyword=$Distance` TO result.
    APPEND `Keyword=$Probability` TO result.
    APPEND `Keyword=$ProbabilityStDev` TO result.
    APPEND `Keyword=$ProbabilityStdDeV` TO result.
    APPEND `Keyword=$ProbabilityVariance` TO result.
    APPEND `Keyword=$StDev` TO result.
    APPEND `Keyword=$StdDeV` TO result.
    APPEND `Keyword=$Support` TO result.
    APPEND `Keyword=$Variance` TO result.
    APPEND `Keyword=AddCalculatedMembers` TO result.
    APPEND `Keyword=Action` TO result.
    APPEND `Keyword=After` TO result.
    APPEND `Keyword=Aggregate` TO result.
    APPEND `Keyword=All` TO result.
    APPEND `Keyword=Alter` TO result.
    APPEND `Keyword=Ancestor` TO result.
    APPEND `Keyword=And` TO result.
    APPEND `Keyword=Append` TO result.
    APPEND `Keyword=As` TO result.
    APPEND `Keyword=ASC` TO result.
    APPEND `Keyword=Axis` TO result.
    APPEND `Keyword=Automatic` TO result.
    APPEND `Keyword=Back_Color` TO result.
    APPEND `Keyword=BASC` TO result.
    APPEND `Keyword=BDESC` TO result.
    APPEND `Keyword=Before` TO result.
    APPEND `Keyword=Before_And_After` TO result.
    APPEND `Keyword=Before_And_Self` TO result.
    APPEND `Keyword=Before_Self_After` TO result.
    APPEND `Keyword=BottomCount` TO result.
    APPEND `Keyword=BottomPercent` TO result.
    APPEND `Keyword=BottomSum` TO result.
    APPEND `Keyword=Break` TO result.
    APPEND `Keyword=Boolean` TO result.
    APPEND `Keyword=Cache` TO result.
    APPEND `Keyword=Calculated` TO result.
    APPEND `Keyword=Call` TO result.
    APPEND `Keyword=Case` TO result.
    APPEND `Keyword=Catalog_Name` TO result.
    APPEND `Keyword=Cell` TO result.
    APPEND `Keyword=Cell_Ordinal` TO result.
    APPEND `Keyword=Cells` TO result.
    APPEND `Keyword=Chapters` TO result.
    APPEND `Keyword=Children` TO result.
    APPEND `Keyword=Children_Cardinality` TO result.
    APPEND `Keyword=ClosingPeriod` TO result.
    APPEND `Keyword=Cluster` TO result.
    APPEND `Keyword=ClusterDistance` TO result.
    APPEND `Keyword=ClusterProbability` TO result.
    APPEND `Keyword=Clusters` TO result.
    APPEND `Keyword=CoalesceEmpty` TO result.
    APPEND `Keyword=Column_Values` TO result.
    APPEND `Keyword=Columns` TO result.
    APPEND `Keyword=Content` TO result.
    APPEND `Keyword=Contingent` TO result.
    APPEND `Keyword=Continuous` TO result.
    APPEND `Keyword=Correlation` TO result.
    APPEND `Keyword=Cousin` TO result.
    APPEND `Keyword=Covariance` TO result.
    APPEND `Keyword=CovarianceN` TO result.
    APPEND `Keyword=Create` TO result.
    APPEND `Keyword=CreatePropertySet` TO result.
    APPEND `Keyword=CrossJoin` TO result.
    APPEND `Keyword=Cube` TO result.
    APPEND `Keyword=Cube_Name` TO result.
    APPEND `Keyword=CurrentMember` TO result.
    APPEND `Keyword=CurrentCube` TO result.
    APPEND `Keyword=Custom` TO result.
    APPEND `Keyword=Cyclical` TO result.
    APPEND `Keyword=DefaultMember` TO result.
    APPEND `Keyword=Default_Member` TO result.
    APPEND `Keyword=DESC` TO result.
    APPEND `Keyword=Descendents` TO result.
    APPEND `Keyword=Description` TO result.
    APPEND `Keyword=Dimension` TO result.
    APPEND `Keyword=Dimension_Unique_Name` TO result.
    APPEND `Keyword=Dimensions` TO result.
    APPEND `Keyword=Discrete` TO result.
    APPEND `Keyword=Discretized` TO result.
    APPEND `Keyword=DrillDownLevel` TO result.
    APPEND `Keyword=DrillDownLevelBottom` TO result.
    APPEND `Keyword=DrillDownLevelTop` TO result.
    APPEND `Keyword=DrillDownMember` TO result.
    APPEND `Keyword=DrillDownMemberBottom` TO result.
    APPEND `Keyword=DrillDownMemberTop` TO result.
    APPEND `Keyword=DrillTrough` TO result.
    APPEND `Keyword=DrillUpLevel` TO result.
    APPEND `Keyword=DrillUpMember` TO result.
    APPEND `Keyword=Drop` TO result.
    APPEND `Keyword=Else` TO result.
    APPEND `Keyword=Empty` TO result.
    APPEND `Keyword=End` TO result.
    APPEND `Keyword=Equal_Areas` TO result.
    APPEND `Keyword=Exclude_Null` TO result.
    APPEND `Keyword=ExcludeEmpty` TO result.
    APPEND `Keyword=Exclusive` TO result.
    APPEND `Keyword=Expression` TO result.
    APPEND `Keyword=Filter` TO result.
    APPEND `Keyword=FirstChild` TO result.
    APPEND `Keyword=FirstRowset` TO result.
    APPEND `Keyword=FirstSibling` TO result.
    APPEND `Keyword=Flattened` TO result.
    APPEND `Keyword=Font_Flags` TO result.
    APPEND `Keyword=Font_Name` TO result.
    APPEND `Keyword=Font_size` TO result.
    APPEND `Keyword=Fore_Color` TO result.
    APPEND `Keyword=Format_String` TO result.
    APPEND `Keyword=Formatted_Value` TO result.
    APPEND `Keyword=Formula` TO result.
    APPEND `Keyword=From` TO result.
    APPEND `Keyword=Generate` TO result.
    APPEND `Keyword=Global` TO result.
    APPEND `Keyword=Head` TO result.
    APPEND `Keyword=Hierarchize` TO result.
    APPEND `Keyword=Hierarchy` TO result.
    APPEND `Keyword=Hierary_Unique_name` TO result.
    APPEND `Keyword=IIF` TO result.
    APPEND `Keyword=IsEmpty` TO result.
    APPEND `Keyword=Include_Null` TO result.
    APPEND `Keyword=Include_Statistics` TO result.
    APPEND `Keyword=Inclusive` TO result.
    APPEND `Keyword=Input_Only` TO result.
    APPEND `Keyword=IsDescendant` TO result.
    APPEND `Keyword=Item` TO result.
    APPEND `Keyword=Lag` TO result.
    APPEND `Keyword=LastChild` TO result.
    APPEND `Keyword=LastPeriods` TO result.
    APPEND `Keyword=LastSibling` TO result.
    APPEND `Keyword=Lead` TO result.
    APPEND `Keyword=Level` TO result.
    APPEND `Keyword=Level_Number` TO result.
    APPEND `Keyword=Level_Unique_Name` TO result.
    APPEND `Keyword=Levels` TO result.
    APPEND `Keyword=LinRegIntercept` TO result.
    APPEND `Keyword=LinRegR2` TO result.
    APPEND `Keyword=LinRegPoint` TO result.
    APPEND `Keyword=LinRegSlope` TO result.
    APPEND `Keyword=LinRegVariance` TO result.
    APPEND `Keyword=Long` TO result.
    APPEND `Keyword=MaxRows` TO result.
    APPEND `Keyword=Median` TO result.
    APPEND `Keyword=Member` TO result.
    APPEND `Keyword=Member_Caption` TO result.
    APPEND `Keyword=Member_Guid` TO result.
    APPEND `Keyword=Member_Name` TO result.
    APPEND `Keyword=Member_Ordinal` TO result.
    APPEND `Keyword=Member_Type` TO result.
    APPEND `Keyword=Member_Unique_Name` TO result.
    APPEND `Keyword=Members` TO result.
    APPEND `Keyword=Microsoft_Clustering` TO result.
    APPEND `Keyword=Microsoft_Decision_Trees` TO result.
    APPEND `Keyword=Mining` TO result.
    APPEND `Keyword=Model` TO result.
    APPEND `Keyword=Model_Existence_Only` TO result.
    APPEND `Keyword=Models` TO result.
    APPEND `Keyword=Move` TO result.
    APPEND `Keyword=MTD` TO result.
    APPEND `Keyword=Name` TO result.
    APPEND `Keyword=Nest` TO result.
    APPEND `Keyword=NextMember` TO result.
    APPEND `Keyword=Non` TO result.
    APPEND `Keyword=NonEmpty` TO result.
    APPEND `Keyword=Normal` TO result.
    APPEND `Keyword=Not` TO result.
    APPEND `Keyword=Ntext` TO result.
    APPEND `Keyword=Nvarchar` TO result.
    APPEND `Keyword=OLAP` TO result.
    APPEND `Keyword=On` TO result.
    APPEND `Keyword=OpeningPeriod` TO result.
    APPEND `Keyword=OpenQuery` TO result.
    APPEND `Keyword=Or` TO result.
    APPEND `Keyword=Ordered` TO result.
    APPEND `Keyword=Ordinal` TO result.
    APPEND `Keyword=Pages` TO result.
    APPEND `Keyword=ParallelPeriod` TO result.
    APPEND `Keyword=Parent` TO result.
    APPEND `Keyword=Parent_Level` TO result.
    APPEND `Keyword=Parent_Unique_Name` TO result.
    APPEND `Keyword=PeriodsToDate` TO result.
    APPEND `Keyword=PMML` TO result.
    APPEND `Keyword=Predict` TO result.
    APPEND `Keyword=Predict_Only` TO result.
    APPEND `Keyword=PredictAdjustedProbability` TO result.
    APPEND `Keyword=PredictHistogram` TO result.
    APPEND `Keyword=Prediction` TO result.
    APPEND `Keyword=PredictionScore` TO result.
    APPEND `Keyword=PredictProbability` TO result.
    APPEND `Keyword=PredictProbabilityStDev` TO result.
    APPEND `Keyword=PredictProbabilityVariance` TO result.
    APPEND `Keyword=PredictStDev` TO result.
    APPEND `Keyword=PredictSupport` TO result.
    APPEND `Keyword=PredictVariance` TO result.
    APPEND `Keyword=PrevMember` TO result.
    APPEND `Keyword=Probability` TO result.
    APPEND `Keyword=Probability_StDev` TO result.
    APPEND `Keyword=Probability_StdDev` TO result.
    APPEND `Keyword=Probability_Variance` TO result.
    APPEND `Keyword=Properties` TO result.
    APPEND `Keyword=Property` TO result.
    APPEND `Keyword=QTD` TO result.
    APPEND `Keyword=RangeMax` TO result.
    APPEND `Keyword=RangeMid` TO result.
    APPEND `Keyword=RangeMin` TO result.
    APPEND `Keyword=Rank` TO result.
    APPEND `Keyword=Recursive` TO result.
    APPEND `Keyword=Refresh` TO result.
    APPEND `Keyword=Related` TO result.
    APPEND `Keyword=Rename` TO result.
    APPEND `Keyword=Rollup` TO result.
    APPEND `Keyword=Rows` TO result.
    APPEND `Keyword=Schema_Name` TO result.
    APPEND `Keyword=Sections` TO result.
    APPEND `Keyword=Select` TO result.
    APPEND `Keyword=Self` TO result.
    APPEND `Keyword=Self_And_After` TO result.
    APPEND `Keyword=Sequence_Time` TO result.
    APPEND `Keyword=Server` TO result.
    APPEND `Keyword=Session` TO result.
    APPEND `Keyword=Set` TO result.
    APPEND `Keyword=SetToArray` TO result.
    APPEND `Keyword=SetToStr` TO result.
    APPEND `Keyword=Shape` TO result.
    APPEND `Keyword=Skip` TO result.
    APPEND `Keyword=Solve_Order` TO result.
    APPEND `Keyword=Sort` TO result.
    APPEND `Keyword=StdDev` TO result.
    APPEND `Keyword=Stdev` TO result.
    APPEND `Keyword=StripCalculatedMembers` TO result.
    APPEND `Keyword=StrToSet` TO result.
    APPEND `Keyword=StrToTuple` TO result.
    APPEND `Keyword=SubSet` TO result.
    APPEND `Keyword=Support` TO result.
    APPEND `Keyword=Tail` TO result.
    APPEND `Keyword=Text` TO result.
    APPEND `Keyword=Thresholds` TO result.
    APPEND `Keyword=ToggleDrillState` TO result.
    APPEND `Keyword=TopCount` TO result.
    APPEND `Keyword=TopPercent` TO result.
    APPEND `Keyword=TopSum` TO result.
    APPEND `Keyword=TupleToStr` TO result.
    APPEND `Keyword=Under` TO result.
    APPEND `Keyword=Uniform` TO result.
    APPEND `Keyword=UniqueName` TO result.
    APPEND `Keyword=Use` TO result.
    APPEND `Keyword=Value` TO result.
    APPEND `Keyword=Var` TO result.
    APPEND `Keyword=Variance` TO result.
    APPEND `Keyword=VarP` TO result.
    APPEND `Keyword=VarianceP` TO result.
    APPEND `Keyword=VisualTotals` TO result.
    APPEND `Keyword=When` TO result.
    APPEND `Keyword=Where` TO result.
    APPEND `Keyword=With` TO result.
    APPEND `Keyword=WTD` TO result.
    APPEND `Keyword=Xor` TO result.
  ENDMETHOD.

  METHOD literals.
    APPEND `LiteralName=DBLITERAL_CATALOG_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=24~LiteralNameEnumValue=2` TO result.
    APPEND `LiteralName=DBLITERAL_CATALOG_SEPARATOR~LiteralValue=.~LiteralMaxLength=0~LiteralNameEnumValue=3` TO result.
    APPEND `LiteralName=DBLITERAL_COLUMN_ALIAS~LiteralInvalidChars='"[]~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=5` TO result.
    APPEND `LiteralName=DBLITERAL_COLUMN_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=6` TO result.
    APPEND `LiteralName=DBLITERAL_CORRELATION_NAME~LiteralInvalidChars='"[]~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=7` TO result.
    APPEND `LiteralName=DBLITERAL_CUBE_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=21` TO result.
    APPEND `LiteralName=DBLITERAL_DIMENSION_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=22` TO result.
    APPEND `LiteralName=DBLITERAL_HIERARCHY_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=23` TO result.
    APPEND `LiteralName=DBLITERAL_LEVEL_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=24` TO result.
    APPEND `LiteralName=DBLITERAL_MEMBER_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=25` TO result.
    APPEND `LiteralName=DBLITERAL_PROCEDURE_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=14` TO result.
    APPEND `LiteralName=DBLITERAL_PROPERTY_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=26` TO result.
    APPEND `LiteralName=DBLITERAL_QUOTE~LiteralValue=[~LiteralMaxLength=-1~LiteralNameEnumValue=15` TO result.
    APPEND `LiteralName=DBLITERAL_QUOTE_SUFFIX~LiteralValue=]~LiteralMaxLength=-1~LiteralNameEnumValue=28` TO result.
    APPEND `LiteralName=DBLITERAL_TABLE_NAME~LiteralInvalidChars=.~LiteralInvalidStartingChars=0123456789~LiteralMaxLength=-1~LiteralNameEnumValue=17` TO result.
    APPEND `LiteralName=DBLITERAL_TEXT_COMMAND~LiteralMaxLength=-1~LiteralNameEnumValue=18` TO result.
    APPEND `LiteralName=DBLITERAL_USER_NAME~LiteralMaxLength=0~LiteralNameEnumValue=19` TO result.
  ENDMETHOD.

  METHOD provider_types.
    APPEND `TYPE_NAME=INTEGER~DATA_TYPE=3~COLUMN_SIZE=8~IS_NULLABLE=true~UNSIGNED_ATTRIBUTE=false~FIXED_PREC_SCALE=false~AUTO_UNIQUE_VALUE=false~IS_LONG=false~BES` &&
        `T_MATCH=true` TO result.
    APPEND `TYPE_NAME=DOUBLE~DATA_TYPE=5~COLUMN_SIZE=16~IS_NULLABLE=true~UNSIGNED_ATTRIBUTE=false~FIXED_PREC_SCALE=false~AUTO_UNIQUE_VALUE=false~IS_LONG=false~BES` &&
        `T_MATCH=true` TO result.
    APPEND `TYPE_NAME=CURRENCY~DATA_TYPE=6~COLUMN_SIZE=8~IS_NULLABLE=true~UNSIGNED_ATTRIBUTE=false~FIXED_PREC_SCALE=false~AUTO_UNIQUE_VALUE=false~IS_LONG=false~BE` &&
        `ST_MATCH=true` TO result.
    APPEND `TYPE_NAME=BOOLEAN~DATA_TYPE=11~COLUMN_SIZE=1~IS_NULLABLE=true~UNSIGNED_ATTRIBUTE=false~FIXED_PREC_SCALE=false~AUTO_UNIQUE_VALUE=false~IS_LONG=false~BE` &&
        `ST_MATCH=true` TO result.
    APPEND `TYPE_NAME=LARGE_INTEGER~DATA_TYPE=20~COLUMN_SIZE=16~IS_NULLABLE=true~UNSIGNED_ATTRIBUTE=false~FIXED_PREC_SCALE=false~AUTO_UNIQUE_VALUE=false~IS_LONG=f` &&
        `alse~BEST_MATCH=true` TO result.
    APPEND `TYPE_NAME=STRING~DATA_TYPE=130~COLUMN_SIZE=255~LITERAL_PREFIX="~LITERAL_SUFFIX="~IS_NULLABLE=true~CASE_SENSITIVE=false~FIXED_PREC_SCALE=false~AUTO_UNI` &&
        `QUE_VALUE=false~IS_LONG=false~BEST_MATCH=true` TO result.
  ENDMETHOD.

  METHOD functions.
    APPEND `FUNCTION_NAME=*~DESCRIPTION=Multiplies two numbers.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTI` &&
        `ON=*` TO result.
    APPEND `FUNCTION_NAME=*~DESCRIPTION=Returns the cross product of two sets.~PARAMETER_LIST=Set, Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=*` TO result.
    APPEND `FUNCTION_NAME=*~DESCRIPTION=Returns the cross product of two sets.~PARAMETER_LIST=Member, Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=*` TO result.
    APPEND `FUNCTION_NAME=*~DESCRIPTION=Returns the cross product of two sets.~PARAMETER_LIST=Set, Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=*` TO result.
    APPEND `FUNCTION_NAME=*~DESCRIPTION=Returns the cross product of two sets.~PARAMETER_LIST=Member, Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=*` TO result.
    APPEND `FUNCTION_NAME=+~DESCRIPTION=Adds two numbers.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=+` TO result.
    APPEND `FUNCTION_NAME=-~DESCRIPTION=Subtracts two numbers.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTIO` &&
        `N=-` TO result.
    APPEND `FUNCTION_NAME=-~DESCRIPTION=Returns the negative of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=-` TO result.
    APPEND `FUNCTION_NAME=-~DESCRIPTION=Finds the difference between two sets.~PARAMETER_LIST=Set, Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=-` TO result.
    APPEND `FUNCTION_NAME=-~DESCRIPTION=Finds the difference between all members and set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=-` TO result.
    APPEND `FUNCTION_NAME=/~DESCRIPTION=Divides two numbers.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=` &&
        `/` TO result.
    APPEND `FUNCTION_NAME=:~DESCRIPTION=Infix colon operator returns the set of members between a given pair of members.~PARAMETER_LIST=Member, Member~RETURN_TYPE` &&
        `=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=:` TO result.
    APPEND `FUNCTION_NAME=<~DESCRIPTION=Returns whether an expression is less than another.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=11~O` &&
        `RIGIN=1~INTERFACE_NAME=~CAPTION=<` TO result.
    APPEND `FUNCTION_NAME=<~DESCRIPTION=Returns whether an expression is less than another.~PARAMETER_LIST=String, String~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~` &&
        `CAPTION=<` TO result.
    APPEND `FUNCTION_NAME=<=~DESCRIPTION=Returns whether an expression is less than or equal to another.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RET` &&
        `URN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=<=` TO result.
    APPEND `FUNCTION_NAME=<=~DESCRIPTION=Returns whether an expression is less than or equal to another.~PARAMETER_LIST=String, String~RETURN_TYPE=11~ORIGIN=1~INT` &&
        `ERFACE_NAME=~CAPTION=<=` TO result.
    APPEND `FUNCTION_NAME=<>~DESCRIPTION=Returns whether two expressions are not equal.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=11~ORIGI` &&
        `N=1~INTERFACE_NAME=~CAPTION=<>` TO result.
    APPEND `FUNCTION_NAME=<>~DESCRIPTION=Returns whether two expressions are not equal.~PARAMETER_LIST=String, String~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPT` &&
        `ION=<>` TO result.
    APPEND `FUNCTION_NAME==~DESCRIPTION=Returns whether two logical expressions are equal.~PARAMETER_LIST=Logical Expression, Logical Expression~RETURN_TYPE=11~OR` &&
        `IGIN=1~INTERFACE_NAME=~CAPTION==` TO result.
    APPEND `FUNCTION_NAME==~DESCRIPTION=Returns whether two expressions are equal.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=11~ORIGIN=1~I` &&
        `NTERFACE_NAME=~CAPTION==` TO result.
    APPEND `FUNCTION_NAME==~DESCRIPTION=Returns whether two expressions are equal.~PARAMETER_LIST=String, String~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION==` TO result.
    APPEND `FUNCTION_NAME=>~DESCRIPTION=Returns whether an expression is greater than another.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=1` &&
        `1~ORIGIN=1~INTERFACE_NAME=~CAPTION=>` TO result.
    APPEND `FUNCTION_NAME=>~DESCRIPTION=Returns whether an expression is greater than another.~PARAMETER_LIST=String, String~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAM` &&
        `E=~CAPTION=>` TO result.
    APPEND `FUNCTION_NAME=>=~DESCRIPTION=Returns whether an expression is greater than or equal to another.~PARAMETER_LIST=Numeric Expression, Numeric Expression~` &&
        `RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=>=` TO result.
    APPEND `FUNCTION_NAME=>=~DESCRIPTION=Returns whether an expression is greater than or equal to another.~PARAMETER_LIST=String, String~RETURN_TYPE=11~ORIGIN=1~` &&
        `INTERFACE_NAME=~CAPTION=>=` TO result.
    APPEND `FUNCTION_NAME=_CaseMatch~DESCRIPTION=Evaluates various expressions, and returns the corresponding expression for the first which matches a particular ` &&
        `value.~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=_CaseMatch` TO result.
    APPEND `FUNCTION_NAME=_CaseTest~DESCRIPTION=Evaluates various conditions, and returns the corresponding expression for the first which evaluates to true.~PARA` &&
        `METER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=_CaseTest` TO result.
    APPEND `FUNCTION_NAME=Abs~DESCRIPTION=Returns a value of the same type that is passed to it specifying the absolute value of a number.~PARAMETER_LIST=Numeric ` &&
        `Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Abs` TO result.
    APPEND `FUNCTION_NAME=Acos~DESCRIPTION=Returns the arccosine, or inverse cosine, of a number. The arccosine is the angle whose cosine is Arg1. The returned an` &&
        `gle is given in radians in the range 0 (zero) to pi.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Acos` TO result.
    APPEND `FUNCTION_NAME=Acosh~DESCRIPTION=Returns the inverse hyperbolic cosine of a number. Number must be greater than or equal to 1. The inverse hyperbolic c` &&
        `osine is the value whose hyperbolic cosine is Arg1, so Acosh(Cosh(number)) equals Arg1.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTER` &&
        `FACE_NAME=~CAPTION=Acosh` TO result.
    APPEND `FUNCTION_NAME=AddCalculatedMembers~DESCRIPTION=Adds calculated members to a set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Ad` &&
        `dCalculatedMembers` TO result.
    APPEND `FUNCTION_NAME=Aggregate~DESCRIPTION=Returns a calculated value using the appropriate aggregate function, based on the context of the query.~PARAMETER_` &&
        `LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Aggregate` TO result.
    APPEND `FUNCTION_NAME=Aggregate~DESCRIPTION=Returns a calculated value using the appropriate aggregate function, based on the context of the query.~PARAMETER_` &&
        `LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Aggregate` TO result.
    APPEND `FUNCTION_NAME=AllMembers~DESCRIPTION=Returns a set that contains all members, including calculated members, of the specified hierarchy.~PARAMETER_LIST` &&
        `=Hierarchy~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=AllMembers` TO result.
    APPEND `FUNCTION_NAME=AllMembers~DESCRIPTION=Returns a set that contains all members, including calculated members, of the specified level.~PARAMETER_LIST=Lev` &&
        `el~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=AllMembers` TO result.
    APPEND `FUNCTION_NAME=Ancestor~DESCRIPTION=Returns the ancestor of a member at a specified level.~PARAMETER_LIST=Member, Level~RETURN_TYPE=12~ORIGIN=1~INTERFA` &&
        `CE_NAME=~CAPTION=Ancestor` TO result.
    APPEND `FUNCTION_NAME=Ancestor~DESCRIPTION=Returns the ancestor of a member at a specified level.~PARAMETER_LIST=Member, Numeric Expression~RETURN_TYPE=12~ORI` &&
        `GIN=1~INTERFACE_NAME=~CAPTION=Ancestor` TO result.
    APPEND `FUNCTION_NAME=Ancestors~DESCRIPTION=Returns the set of all ancestors of a specified member at a specified level or at a specified distance from the me` &&
        `mber~PARAMETER_LIST=Member, Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Ancestors` TO result.
    APPEND `FUNCTION_NAME=Ancestors~DESCRIPTION=Returns the set of all ancestors of a specified member at a specified level or at a specified distance from the me` &&
        `mber~PARAMETER_LIST=Member, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Ancestors` TO result.
    APPEND `FUNCTION_NAME=AND~DESCRIPTION=Returns the conjunction of two conditions.~PARAMETER_LIST=Logical Expression, Logical Expression~RETURN_TYPE=11~ORIGIN=1` &&
        `~INTERFACE_NAME=~CAPTION=AND` TO result.
    APPEND `FUNCTION_NAME=AS~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=AS` TO result.
    APPEND `FUNCTION_NAME=Asc~DESCRIPTION=Returns an Integer representing the character code corresponding to the first letter in a string.~PARAMETER_LIST=String~` &&
        `RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Asc` TO result.
    APPEND `FUNCTION_NAME=AscB~DESCRIPTION=See Asc.~PARAMETER_LIST=String~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=AscB` TO result.
    APPEND `FUNCTION_NAME=Ascendants~DESCRIPTION=Returns the set of the ascendants of a specified member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_` &&
        `NAME=~CAPTION=Ascendants` TO result.
    APPEND `FUNCTION_NAME=AscW~DESCRIPTION=See Asc.~PARAMETER_LIST=String~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=AscW` TO result.
    APPEND `FUNCTION_NAME=Asin~DESCRIPTION=Returns the arcsine, or inverse sine, of a number. The arcsine is the angle whose sine is Arg1. The returned angle is g` &&
        `iven in radians in the range -pi/2 to pi/2.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Asin` TO result.
    APPEND `FUNCTION_NAME=Asinh~DESCRIPTION=Returns the inverse hyperbolic sine of a number. The inverse hyperbolic sine is the value whose hyperbolic sine is Arg` &&
        `1, so Asinh(Sinh(number)) equals Arg1.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Asinh` TO result.
    APPEND `FUNCTION_NAME=Atan2~DESCRIPTION=Returns the arctangent, or inverse tangent, of the specified x- and y-coordinates. The arctangent is the angle from th` &&
        `e x-axis to a line containing the origin (0, 0) and a point with coordinates (x_num, y_num). The angle is given in radians between -pi and pi, excludi` &&
        `ng -pi.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Atan2` TO result.
    APPEND `FUNCTION_NAME=Atanh~DESCRIPTION=Returns the inverse hyperbolic tangent of a number. Number must be between -1 and 1 (excluding -1 and 1).~PARAMETER_LI` &&
        `ST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Atanh` TO result.
    APPEND `FUNCTION_NAME=Atn~DESCRIPTION=Returns a Double specifying the arctangent of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFA` &&
        `CE_NAME=~CAPTION=Atn` TO result.
    APPEND `FUNCTION_NAME=Avg~DESCRIPTION=Returns the average value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=Avg` TO result.
    APPEND `FUNCTION_NAME=Avg~DESCRIPTION=Returns the average value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TY` &&
        `PE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Avg` TO result.
    APPEND `FUNCTION_NAME=BottomCount~DESCRIPTION=Returns a specified number of items from the bottom of a set, optionally ordering the set first.~PARAMETER_LIST=` &&
        `Set, Numeric Expression, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=BottomCount` TO result.
    APPEND `FUNCTION_NAME=BottomCount~DESCRIPTION=Returns a specified number of items from the bottom of a set, optionally ordering the set first.~PARAMETER_LIST=` &&
        `Set, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=BottomCount` TO result.
    APPEND `FUNCTION_NAME=BottomPercent~DESCRIPTION=Sorts a set and returns the bottom N elements whose cumulative total is at least a specified percentage.~PARAM` &&
        `ETER_LIST=Set, Numeric Expression, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=BottomPercent` TO result.
    APPEND `FUNCTION_NAME=BottomSum~DESCRIPTION=Sorts a set and returns the bottom N elements whose cumulative total is at least a specified value.~PARAMETER_LIST` &&
        `=Set, Numeric Expression, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=BottomSum` TO result.
    APPEND `FUNCTION_NAME=Cache~DESCRIPTION=Evaluates and returns its sole argument, applying statement-level caching~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1` &&
        `~INTERFACE_NAME=~CAPTION=Cache` TO result.
    APPEND `FUNCTION_NAME=CachedExists~DESCRIPTION=Returns tuples from a non-dynamic <Set> that exists in the specified <Tuple>.  This function will build a query` &&
        ` level cache named <String> based on the <Tuple> type.~PARAMETER_LIST=Set, Tuple, String~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=CachedExists` TO result.
    APPEND `FUNCTION_NAME=CalculatedChild~DESCRIPTION=Returns an existing calculated child member with name <String> from the specified <Member>.~PARAMETER_LIST=M` &&
        `ember, String~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=CalculatedChild` TO result.
    APPEND `FUNCTION_NAME=Caption~DESCRIPTION=Returns the caption of a dimension.~PARAMETER_LIST=Dimension~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Caption` TO result.
    APPEND `FUNCTION_NAME=Caption~DESCRIPTION=Returns the caption of a hierarchy.~PARAMETER_LIST=Hierarchy~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Caption` TO result.
    APPEND `FUNCTION_NAME=Caption~DESCRIPTION=Returns the caption of a level.~PARAMETER_LIST=Level~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Caption` TO result.
    APPEND `FUNCTION_NAME=Caption~DESCRIPTION=Returns the caption of a member.~PARAMETER_LIST=Member~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Caption` TO result.
    APPEND `FUNCTION_NAME=Cast~DESCRIPTION=Converts values to another type.~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=Cast` TO result.
    APPEND `FUNCTION_NAME=CBool~DESCRIPTION=Returns an expression that has been converted to a Variant of subtype Boolean.~PARAMETER_LIST=Value~RETURN_TYPE=11~ORI` &&
        `GIN=1~INTERFACE_NAME=~CAPTION=CBool` TO result.
    APPEND `FUNCTION_NAME=CByte~DESCRIPTION=Returns an expression that has been converted to a Variant of subtype Byte.~PARAMETER_LIST=Value~RETURN_TYPE=2~ORIGIN=` &&
        `1~INTERFACE_NAME=~CAPTION=CByte` TO result.
    APPEND `FUNCTION_NAME=CDate~DESCRIPTION=Returns an expression that has been converted to a Variant of subtype Date.~PARAMETER_LIST=Value~RETURN_TYPE=7~ORIGIN=` &&
        `1~INTERFACE_NAME=~CAPTION=CDate` TO result.
    APPEND `FUNCTION_NAME=CDbl~DESCRIPTION=Returns an expression that has been converted to a Variant of subtype Double.~PARAMETER_LIST=Value~RETURN_TYPE=5~ORIGIN` &&
        `=1~INTERFACE_NAME=~CAPTION=CDbl` TO result.
    APPEND `FUNCTION_NAME=Children~DESCRIPTION=Returns the children of a member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Children` TO result.
    APPEND `FUNCTION_NAME=Chr~DESCRIPTION=Returns a String containing the character associated with the specified character code.~PARAMETER_LIST=Integer~RETURN_TY` &&
        `PE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Chr` TO result.
    APPEND `FUNCTION_NAME=ChrB~DESCRIPTION=See Chr.~PARAMETER_LIST=Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=ChrB` TO result.
    APPEND `FUNCTION_NAME=ChrW~DESCRIPTION=See Chr.~PARAMETER_LIST=Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=ChrW` TO result.
    APPEND `FUNCTION_NAME=CInt~DESCRIPTION=Returns an expression that has been converted to a Variant of subtype Integer.~PARAMETER_LIST=Value~RETURN_TYPE=2~ORIGI` &&
        `N=1~INTERFACE_NAME=~CAPTION=CInt` TO result.
    APPEND `FUNCTION_NAME=ClosingPeriod~DESCRIPTION=Returns the last descendant of a member at a level.~PARAMETER_LIST=~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CA` &&
        `PTION=ClosingPeriod` TO result.
    APPEND `FUNCTION_NAME=ClosingPeriod~DESCRIPTION=Returns the last descendant of a member at a level.~PARAMETER_LIST=Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAM` &&
        `E=~CAPTION=ClosingPeriod` TO result.
    APPEND `FUNCTION_NAME=ClosingPeriod~DESCRIPTION=Returns the last descendant of a member at a level.~PARAMETER_LIST=Level, Member~RETURN_TYPE=12~ORIGIN=1~INTER` &&
        `FACE_NAME=~CAPTION=ClosingPeriod` TO result.
    APPEND `FUNCTION_NAME=ClosingPeriod~DESCRIPTION=Returns the last descendant of a member at a level.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NA` &&
        `ME=~CAPTION=ClosingPeriod` TO result.
    APPEND `FUNCTION_NAME=CoalesceEmpty~DESCRIPTION=Coalesces an empty cell value to a different value. All of the expressions must be of the same type (number or` &&
        ` string).~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=CoalesceEmpty` TO result.
    APPEND `FUNCTION_NAME=Correlation~DESCRIPTION=Returns the correlation of two series evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=5` &&
        `~ORIGIN=1~INTERFACE_NAME=~CAPTION=Correlation` TO result.
    APPEND `FUNCTION_NAME=Correlation~DESCRIPTION=Returns the correlation of two series evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression, Numeric Expr` &&
        `ession~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Correlation` TO result.
    APPEND `FUNCTION_NAME=Cos~DESCRIPTION=Returns a Double specifying the cosine of an angle.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_N` &&
        `AME=~CAPTION=Cos` TO result.
    APPEND `FUNCTION_NAME=Cosh~DESCRIPTION=Returns the hyperbolic cosine of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAP` &&
        `TION=Cosh` TO result.
    APPEND `FUNCTION_NAME=Count~DESCRIPTION=Returns the number of tuples in a set, empty cells included unless the optional EXCLUDEEMPTY flag is used.~PARAMETER_L` &&
        `IST=Set~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Count` TO result.
    APPEND `FUNCTION_NAME=Count~DESCRIPTION=Returns the number of tuples in a set, empty cells included unless the optional EXCLUDEEMPTY flag is used.~PARAMETER_L` &&
        `IST=Set, Symbol~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Count` TO result.
    APPEND `FUNCTION_NAME=Count~DESCRIPTION=Returns the number of tuples in a set including empty cells.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=` &&
        `~CAPTION=Count` TO result.
    APPEND `FUNCTION_NAME=Cousin~DESCRIPTION=Returns the member with the same relative position under <ancestor member> as the member specified.~PARAMETER_LIST=Me` &&
        `mber, Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Cousin` TO result.
    APPEND `FUNCTION_NAME=Covariance~DESCRIPTION=Returns the covariance of two series evaluated over a set (biased).~PARAMETER_LIST=Set, Numeric Expression~RETURN` &&
        `_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Covariance` TO result.
    APPEND `FUNCTION_NAME=Covariance~DESCRIPTION=Returns the covariance of two series evaluated over a set (biased).~PARAMETER_LIST=Set, Numeric Expression, Numer` &&
        `ic Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Covariance` TO result.
    APPEND `FUNCTION_NAME=CovarianceN~DESCRIPTION=Returns the covariance of two series evaluated over a set (unbiased).~PARAMETER_LIST=Set, Numeric Expression~RET` &&
        `URN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=CovarianceN` TO result.
    APPEND `FUNCTION_NAME=CovarianceN~DESCRIPTION=Returns the covariance of two series evaluated over a set (unbiased).~PARAMETER_LIST=Set, Numeric Expression, Nu` &&
        `meric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=CovarianceN` TO result.
    APPEND `FUNCTION_NAME=Crossjoin~DESCRIPTION=Returns the cross product of two sets.~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=Crossj` &&
        `oin` TO result.
    APPEND `FUNCTION_NAME=Current~DESCRIPTION=Returns the current member or tuple of a named set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTI` &&
        `ON=Current` TO result.
    APPEND `FUNCTION_NAME=CurrentDateMember~PARAMETER_LIST=Hierarchy, String, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=CurrentDateMember` TO result.
    APPEND `FUNCTION_NAME=CurrentDateMember~PARAMETER_LIST=Hierarchy, String~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=CurrentDateMember` TO result.
    APPEND `FUNCTION_NAME=CurrentDateString~PARAMETER_LIST=String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=CurrentDateString` TO result.
    APPEND `FUNCTION_NAME=CurrentMember~DESCRIPTION=Returns the current member along a hierarchy during an iteration.~PARAMETER_LIST=Hierarchy~RETURN_TYPE=12~ORIG` &&
        `IN=1~INTERFACE_NAME=~CAPTION=CurrentMember` TO result.
    APPEND `FUNCTION_NAME=CurrentOrdinal~DESCRIPTION=Returns the ordinal of the current iteration through a named set.~PARAMETER_LIST=Set~RETURN_TYPE=2~ORIGIN=1~I` &&
        `NTERFACE_NAME=~CAPTION=CurrentOrdinal` TO result.
    APPEND `FUNCTION_NAME=DataMember~DESCRIPTION=Returns the system-generated data member that is associated with a nonleaf member of a dimension.~PARAMETER_LIST=` &&
        `Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DataMember` TO result.
    APPEND `FUNCTION_NAME=Date~DESCRIPTION=Returns a Variant (Date) containing the current system date.~PARAMETER_LIST=~RETURN_TYPE=7~ORIGIN=1~INTERFACE_NAME=~CAP` &&
        `TION=Date` TO result.
    APPEND `FUNCTION_NAME=DateAdd~DESCRIPTION=Returns a Variant (Date) containing a date to which a specified time interval has been added.~PARAMETER_LIST=String,` &&
        ` Numeric Expression, DateTime~RETURN_TYPE=7~ORIGIN=1~INTERFACE_NAME=~CAPTION=DateAdd` TO result.
    APPEND `FUNCTION_NAME=DateDiff~DESCRIPTION=Returns a Variant (Long) specifying the number of time intervals between two specified dates.~PARAMETER_LIST=String` &&
        `, DateTime, DateTime, Integer, Integer~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=DateDiff` TO result.
    APPEND `FUNCTION_NAME=DateDiff~DESCRIPTION=Returns a Variant (Long) specifying the number of time intervals between two specified dates.~PARAMETER_LIST=String` &&
        `, DateTime, DateTime, Integer~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=DateDiff` TO result.
    APPEND `FUNCTION_NAME=DateDiff~DESCRIPTION=Returns a Variant (Long) specifying the number of time intervals between two specified dates.~PARAMETER_LIST=String` &&
        `, DateTime, DateTime~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=DateDiff` TO result.
    APPEND `FUNCTION_NAME=DatePart~DESCRIPTION=Returns a Variant (Integer) containing the specified part of a given date.~PARAMETER_LIST=String, DateTime, Integer` &&
        `, Integer~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=DatePart` TO result.
    APPEND `FUNCTION_NAME=DatePart~DESCRIPTION=Returns a Variant (Integer) containing the specified part of a given date.~PARAMETER_LIST=String, DateTime, Integer` &&
        `~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=DatePart` TO result.
    APPEND `FUNCTION_NAME=DatePart~DESCRIPTION=Returns a Variant (Integer) containing the specified part of a given date.~PARAMETER_LIST=String, DateTime~RETURN_T` &&
        `YPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=DatePart` TO result.
    APPEND `FUNCTION_NAME=DateSerial~DESCRIPTION=Returns a Variant (Date) for a specified year, month, and day.~PARAMETER_LIST=Integer, Integer, Integer~RETURN_TY` &&
        `PE=7~ORIGIN=1~INTERFACE_NAME=~CAPTION=DateSerial` TO result.
    APPEND `FUNCTION_NAME=DateValue~DESCRIPTION=Returns a Variant (Date).~PARAMETER_LIST=DateTime~RETURN_TYPE=7~ORIGIN=1~INTERFACE_NAME=~CAPTION=DateValue` TO result.
    APPEND `FUNCTION_NAME=Day~DESCRIPTION=Returns a Variant (Integer) specifying a whole number between 1 and 31, inclusive, representing the day of the month.~PA` &&
        `RAMETER_LIST=DateTime~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Day` TO result.
    APPEND `FUNCTION_NAME=DDB~DESCRIPTION=Returns a Double specifying the depreciation of an asset for a specific time period using the double-declining balance m` &&
        `ethod or some other method you specify.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Numeric Express` &&
        `ion~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=DDB` TO result.
    APPEND `FUNCTION_NAME=DDB~DESCRIPTION=Returns a Double specifying the depreciation of an asset for a specific time period using the double-declining balance m` &&
        `ethod or some other method you specify.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression~RETURN_TYPE=5~OR` &&
        `IGIN=1~INTERFACE_NAME=~CAPTION=DDB` TO result.
    APPEND `FUNCTION_NAME=DefaultMember~DESCRIPTION=Returns the default member of a hierarchy.~PARAMETER_LIST=Hierarchy~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CA` &&
        `PTION=DefaultMember` TO result.
    APPEND `FUNCTION_NAME=Degrees~DESCRIPTION=Converts radians to degrees.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Degree` &&
        `s` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a member at a specified level, optionally including or excluding descendants i` &&
        `n other levels.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a member at a specified level, optionally including or excluding descendants i` &&
        `n other levels.~PARAMETER_LIST=Member, Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a member at a specified level, optionally including or excluding descendants i` &&
        `n other levels.~PARAMETER_LIST=Member, Level, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a member at a specified level, optionally including or excluding descendants i` &&
        `n other levels.~PARAMETER_LIST=Member, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a member at a specified level, optionally including or excluding descendants i` &&
        `n other levels.~PARAMETER_LIST=Member, Numeric Expression, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a member at a specified level, optionally including or excluding descendants i` &&
        `n other levels.~PARAMETER_LIST=Member, Empty, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a set of members at a specified level, optionally including or excluding desce` &&
        `ndants in other levels.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a set of members at a specified level, optionally including or excluding desce` &&
        `ndants in other levels.~PARAMETER_LIST=Set, Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a set of members at a specified level, optionally including or excluding desce` &&
        `ndants in other levels.~PARAMETER_LIST=Set, Level, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a set of members at a specified level, optionally including or excluding desce` &&
        `ndants in other levels.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a set of members at a specified level, optionally including or excluding desce` &&
        `ndants in other levels.~PARAMETER_LIST=Set, Numeric Expression, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Descendants~DESCRIPTION=Returns the set of descendants of a set of members at a specified level, optionally including or excluding desce` &&
        `ndants in other levels.~PARAMETER_LIST=Set, Empty, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Descendants` TO result.
    APPEND `FUNCTION_NAME=Dimension~DESCRIPTION=Returns the dimension that contains a specified hierarchy.~PARAMETER_LIST=Dimension~RETURN_TYPE=12~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=Dimension` TO result.
    APPEND `FUNCTION_NAME=Dimension~DESCRIPTION=Returns the dimension that contains a specified hierarchy.~PARAMETER_LIST=Hierarchy~RETURN_TYPE=12~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=Dimension` TO result.
    APPEND `FUNCTION_NAME=Dimension~DESCRIPTION=Returns the dimension that contains a specified level.~PARAMETER_LIST=Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME` &&
        `=~CAPTION=Dimension` TO result.
    APPEND `FUNCTION_NAME=Dimension~DESCRIPTION=Returns the dimension that contains a specified member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NA` &&
        `ME=~CAPTION=Dimension` TO result.
    APPEND `FUNCTION_NAME=Dimensions~DESCRIPTION=Returns the hierarchy whose zero-based position within the cube is specified by a numeric expression.~PARAMETER_L` &&
        `IST=Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Dimensions` TO result.
    APPEND `FUNCTION_NAME=Dimensions~DESCRIPTION=Returns the hierarchy whose name is specified by a string.~PARAMETER_LIST=String~RETURN_TYPE=12~ORIGIN=1~INTERFAC` &&
        `E_NAME=~CAPTION=Dimensions` TO result.
    APPEND `FUNCTION_NAME=Distinct~DESCRIPTION=Eliminates duplicate tuples from a set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Distinct` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevel~DESCRIPTION=Drills down the members of a set, at a specified level, to one level below. Alternatively, drills down on a s` &&
        `pecified dimension in the set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevel` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevel~DESCRIPTION=Drills down the members of a set, at a specified level, to one level below. Alternatively, drills down on a s` &&
        `pecified dimension in the set.~PARAMETER_LIST=Set, Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevel` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevel~DESCRIPTION=Drills down the members of a set, at a specified level, to one level below. Alternatively, drills down on a s` &&
        `pecified dimension in the set.~PARAMETER_LIST=Set, Empty, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevel` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevel~DESCRIPTION=Drills down the members of a set, at a specified level, to one level below. Alternatively, drills down on a s` &&
        `pecified dimension in the set.~PARAMETER_LIST=Set, Level, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevel` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevel~DESCRIPTION=Drills down the members of a set, at a specified level, to one level below. Alternatively, drills down on a s` &&
        `pecified dimension in the set.~PARAMETER_LIST=Set, Empty, Numeric Expression, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevel` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevel~DESCRIPTION=Drills down the members of a set, at a specified level, to one level below. Alternatively, drills down on a s` &&
        `pecified dimension in the set.~PARAMETER_LIST=Set, Empty, Empty, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevel` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevelBottom~DESCRIPTION=Drills down the bottommost members of a set, at a specified level, to one level below.~PARAMETER_LIST=S` &&
        `et, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevelBottom` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevelBottom~DESCRIPTION=Drills down the bottommost members of a set, at a specified level, to one level below.~PARAMETER_LIST=S` &&
        `et, Numeric Expression, Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevelBottom` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevelBottom~DESCRIPTION=Drills down the bottommost members of a set, at a specified level, to one level below.~PARAMETER_LIST=S` &&
        `et, Numeric Expression, Level, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevelBottom` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevelBottom~DESCRIPTION=Drills down the bottommost members of a set, at a specified level, to one level below.~PARAMETER_LIST=S` &&
        `et, Numeric Expression, Empty, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevelBottom` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevelTop~DESCRIPTION=Drills down the topmost members of a set, at a specified level, to one level below.~PARAMETER_LIST=Set, Nu` &&
        `meric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevelTop` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevelTop~DESCRIPTION=Drills down the topmost members of a set, at a specified level, to one level below.~PARAMETER_LIST=Set, Nu` &&
        `meric Expression, Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevelTop` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevelTop~DESCRIPTION=Drills down the topmost members of a set, at a specified level, to one level below.~PARAMETER_LIST=Set, Nu` &&
        `meric Expression, Level, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevelTop` TO result.
    APPEND `FUNCTION_NAME=DrilldownLevelTop~DESCRIPTION=Drills down the topmost members of a set, at a specified level, to one level below.~PARAMETER_LIST=Set, Nu` &&
        `meric Expression, Empty, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownLevelTop` TO result.
    APPEND `FUNCTION_NAME=DrilldownMember~DESCRIPTION=Drills down the members in a set that are present in a second specified set.~PARAMETER_LIST=Set, Set~RETURN_` &&
        `TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownMember` TO result.
    APPEND `FUNCTION_NAME=DrilldownMember~DESCRIPTION=Drills down the members in a set that are present in a second specified set.~PARAMETER_LIST=Set, Set, Symbol` &&
        `~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownMember` TO result.
    APPEND `FUNCTION_NAME=DrilldownMember~DESCRIPTION=Drills down the members in a set that are present in a second specified set.~PARAMETER_LIST=Set, Set, Empty,` &&
        ` Empty, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrilldownMember` TO result.
    APPEND `FUNCTION_NAME=DrillupLevel~DESCRIPTION=Drills up the members of a set, at a specified level, to one level above.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORI` &&
        `GIN=1~INTERFACE_NAME=~CAPTION=DrillupLevel` TO result.
    APPEND `FUNCTION_NAME=DrillupLevel~DESCRIPTION=Drills up the members of a set, at a specified level, to one level above.~PARAMETER_LIST=Set, Level~RETURN_TYPE` &&
        `=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=DrillupLevel` TO result.
    APPEND `FUNCTION_NAME=Except~DESCRIPTION=Finds the difference between two sets, optionally retaining duplicates.~PARAMETER_LIST=Set, Set~RETURN_TYPE=12~ORIGIN` &&
        `=1~INTERFACE_NAME=~CAPTION=Except` TO result.
    APPEND `FUNCTION_NAME=Except~DESCRIPTION=Finds the difference between two sets, optionally retaining duplicates.~PARAMETER_LIST=Set, Set, Symbol~RETURN_TYPE=1` &&
        `2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Except` TO result.
    APPEND `FUNCTION_NAME=Existing~DESCRIPTION=Forces the set to be evaluated within the current context.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAM` &&
        `E=~CAPTION=Existing` TO result.
    APPEND `FUNCTION_NAME=Exists~DESCRIPTION=Returns the the set of tuples of the first set that exist with one or more tuples of the second set.~PARAMETER_LIST=S` &&
        `et, Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Exists` TO result.
    APPEND `FUNCTION_NAME=Exp~DESCRIPTION=Returns a Double specifying e (the base of natural logarithms) raised to a power.~PARAMETER_LIST=Numeric Expression~RETU` &&
        `RN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Exp` TO result.
    APPEND `FUNCTION_NAME=Extract~DESCRIPTION=Returns a set of tuples from extracted hierarchy elements. The opposite of Crossjoin.~PARAMETER_LIST=(none)~RETURN_T` &&
        `YPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=Extract` TO result.
    APPEND `FUNCTION_NAME=Filter~DESCRIPTION=Returns the set resulting from filtering a set based on a search condition.~PARAMETER_LIST=Set, Logical Expression~RE` &&
        `TURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Filter` TO result.
    APPEND `FUNCTION_NAME=FirstChild~DESCRIPTION=Returns the first child of a member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=FirstC` &&
        `hild` TO result.
    APPEND `FUNCTION_NAME=FirstQ~DESCRIPTION=Returns the 1st quartile value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=` &&
        `1~INTERFACE_NAME=~CAPTION=FirstQ` TO result.
    APPEND `FUNCTION_NAME=FirstQ~DESCRIPTION=Returns the 1st quartile value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression~R` &&
        `ETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=FirstQ` TO result.
    APPEND `FUNCTION_NAME=FirstSibling~DESCRIPTION=Returns the first child of the parent of a member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME` &&
        `=~CAPTION=FirstSibling` TO result.
    APPEND `FUNCTION_NAME=Fix~DESCRIPTION=Returns the integer portion of a number. If negative, returns the negative number greater than or equal to the number.~P` &&
        `ARAMETER_LIST=Value~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Fix` TO result.
    APPEND `FUNCTION_NAME=Format~DESCRIPTION=Formats a number or date to a string.~PARAMETER_LIST=Member, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Fo` &&
        `rmat` TO result.
    APPEND `FUNCTION_NAME=Format~DESCRIPTION=Formats a number or date to a string.~PARAMETER_LIST=Numeric Expression, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME` &&
        `=~CAPTION=Format` TO result.
    APPEND `FUNCTION_NAME=Format~DESCRIPTION=Formats a number or date to a string.~PARAMETER_LIST=DateTime, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=` &&
        `Format` TO result.
    APPEND `FUNCTION_NAME=FormatCurrency~DESCRIPTION=Returns an expression formatted as a currency value using the currency symbol defined in the system control p` &&
        `anel.~PARAMETER_LIST=Value, Integer, Integer, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatCurrency` TO result.
    APPEND `FUNCTION_NAME=FormatCurrency~DESCRIPTION=Returns an expression formatted as a currency value using the currency symbol defined in the system control p` &&
        `anel.~PARAMETER_LIST=Value, Integer, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatCurrency` TO result.
    APPEND `FUNCTION_NAME=FormatCurrency~DESCRIPTION=Returns an expression formatted as a currency value using the currency symbol defined in the system control p` &&
        `anel.~PARAMETER_LIST=Value, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatCurrency` TO result.
    APPEND `FUNCTION_NAME=FormatCurrency~DESCRIPTION=Returns an expression formatted as a currency value using the currency symbol defined in the system control p` &&
        `anel.~PARAMETER_LIST=Value, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatCurrency` TO result.
    APPEND `FUNCTION_NAME=FormatCurrency~DESCRIPTION=Returns an expression formatted as a currency value using the currency symbol defined in the system control p` &&
        `anel.~PARAMETER_LIST=Value~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatCurrency` TO result.
    APPEND `FUNCTION_NAME=FormatDateTime~DESCRIPTION=Returns an expression formatted as a date or time.~PARAMETER_LIST=DateTime, Integer~RETURN_TYPE=8~ORIGIN=1~IN` &&
        `TERFACE_NAME=~CAPTION=FormatDateTime` TO result.
    APPEND `FUNCTION_NAME=FormatDateTime~DESCRIPTION=Returns an expression formatted as a date or time.~PARAMETER_LIST=DateTime~RETURN_TYPE=8~ORIGIN=1~INTERFACE_N` &&
        `AME=~CAPTION=FormatDateTime` TO result.
    APPEND `FUNCTION_NAME=FormatNumber~DESCRIPTION=Returns an expression formatted as a number.~PARAMETER_LIST=Value, Integer, Integer, Integer, Integer~RETURN_TY` &&
        `PE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatNumber` TO result.
    APPEND `FUNCTION_NAME=FormatNumber~DESCRIPTION=Returns an expression formatted as a number.~PARAMETER_LIST=Value, Integer, Integer, Integer~RETURN_TYPE=8~ORIG` &&
        `IN=1~INTERFACE_NAME=~CAPTION=FormatNumber` TO result.
    APPEND `FUNCTION_NAME=FormatNumber~DESCRIPTION=Returns an expression formatted as a number.~PARAMETER_LIST=Value, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTE` &&
        `RFACE_NAME=~CAPTION=FormatNumber` TO result.
    APPEND `FUNCTION_NAME=FormatNumber~DESCRIPTION=Returns an expression formatted as a number.~PARAMETER_LIST=Value, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAM` &&
        `E=~CAPTION=FormatNumber` TO result.
    APPEND `FUNCTION_NAME=FormatNumber~DESCRIPTION=Returns an expression formatted as a number.~PARAMETER_LIST=Value~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTIO` &&
        `N=FormatNumber` TO result.
    APPEND `FUNCTION_NAME=FormatPercent~DESCRIPTION=Returns an expression formatted as a percentage (multipled by 100) with a trailing % character.~PARAMETER_LIST` &&
        `=Value, Integer, Integer, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatPercent` TO result.
    APPEND `FUNCTION_NAME=FormatPercent~DESCRIPTION=Returns an expression formatted as a percentage (multipled by 100) with a trailing % character.~PARAMETER_LIST` &&
        `=Value, Integer, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatPercent` TO result.
    APPEND `FUNCTION_NAME=FormatPercent~DESCRIPTION=Returns an expression formatted as a percentage (multipled by 100) with a trailing % character.~PARAMETER_LIST` &&
        `=Value, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatPercent` TO result.
    APPEND `FUNCTION_NAME=FormatPercent~DESCRIPTION=Returns an expression formatted as a percentage (multipled by 100) with a trailing % character.~PARAMETER_LIST` &&
        `=Value, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatPercent` TO result.
    APPEND `FUNCTION_NAME=FormatPercent~DESCRIPTION=Returns an expression formatted as a percentage (multipled by 100) with a trailing % character.~PARAMETER_LIST` &&
        `=Value~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=FormatPercent` TO result.
    APPEND `FUNCTION_NAME=FV~DESCRIPTION=Returns a Double specifying the future value of an annuity based on periodic, fixed payments and a fixed interest rate.~P` &&
        `ARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Logical Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME` &&
        `=~CAPTION=FV` TO result.
    APPEND `FUNCTION_NAME=FV~DESCRIPTION=Returns a Double specifying the future value of an annuity based on periodic, fixed payments and a fixed interest rate.~P` &&
        `ARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=FV` TO result.
    APPEND `FUNCTION_NAME=FV~DESCRIPTION=Returns a Double specifying the future value of an annuity based on periodic, fixed payments and a fixed interest rate.~P` &&
        `ARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=FV` TO result.
    APPEND `FUNCTION_NAME=Generate~DESCRIPTION=Applies a set to each member of another set and joins the resulting sets by union.~PARAMETER_LIST=Set, Set~RETURN_T` &&
        `YPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Generate` TO result.
    APPEND `FUNCTION_NAME=Generate~DESCRIPTION=Applies a set to each member of another set and joins the resulting sets by union.~PARAMETER_LIST=Set, Set, Symbol~` &&
        `RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Generate` TO result.
    APPEND `FUNCTION_NAME=Generate~DESCRIPTION=Applies a set to a string expression and joins resulting sets by string concatenation.~PARAMETER_LIST=Set, String~R` &&
        `ETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Generate` TO result.
    APPEND `FUNCTION_NAME=Generate~DESCRIPTION=Applies a set to a string expression and joins resulting sets by string concatenation.~PARAMETER_LIST=Set, String, ` &&
        `String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Generate` TO result.
    APPEND `FUNCTION_NAME=Generate~DESCRIPTION=Applies a set to a string expression and joins resulting sets by string concatenation.~PARAMETER_LIST=Set, Numeric ` &&
        `Expression, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Generate` TO result.
    APPEND `FUNCTION_NAME=Head~DESCRIPTION=Returns the first specified number of elements in a set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAP` &&
        `TION=Head` TO result.
    APPEND `FUNCTION_NAME=Head~DESCRIPTION=Returns the first specified number of elements in a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=12~ORIGIN=1` &&
        `~INTERFACE_NAME=~CAPTION=Head` TO result.
    APPEND `FUNCTION_NAME=Hex~DESCRIPTION=Returns a String representing the hexadecimal value of a number.~PARAMETER_LIST=Value~RETURN_TYPE=8~ORIGIN=1~INTERFACE_N` &&
        `AME=~CAPTION=Hex` TO result.
    APPEND `FUNCTION_NAME=Hierarchize~DESCRIPTION=Orders the members of a set in a hierarchy.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=H` &&
        `ierarchize` TO result.
    APPEND `FUNCTION_NAME=Hierarchize~DESCRIPTION=Orders the members of a set in a hierarchy.~PARAMETER_LIST=Set, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~C` &&
        `APTION=Hierarchize` TO result.
    APPEND `FUNCTION_NAME=Hierarchy~DESCRIPTION=Returns a level's hierarchy.~PARAMETER_LIST=Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Hierarchy` TO result.
    APPEND `FUNCTION_NAME=Hierarchy~DESCRIPTION=Returns a member's hierarchy.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Hierarchy` TO result.
    APPEND `FUNCTION_NAME=Hour~DESCRIPTION=Returns a Variant (Integer) specifying a whole number between 0 and 23, inclusive, representing the hour of the day.~PA` &&
        `RAMETER_LIST=DateTime~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Hour` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns one of two tuples determined by a logical test.~PARAMETER_LIST=Logical Expression, Tuple, Tuple~RETURN_TYPE=12~O` &&
        `RIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns one of two dimension values determined by a logical test.~PARAMETER_LIST=Logical Expression, Dimension, Dimensio` &&
        `n~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns one of two hierarchy values determined by a logical test.~PARAMETER_LIST=Logical Expression, Hierarchy, Hierarch` &&
        `y~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns one of two level values determined by a logical test.~PARAMETER_LIST=Logical Expression, Level, Level~RETURN_TYP` &&
        `E=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns boolean determined by a logical test.~PARAMETER_LIST=Logical Expression, Logical Expression, Logical Expression~` &&
        `RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns one of two member values determined by a logical test.~PARAMETER_LIST=Logical Expression, Member, Member~RETURN_` &&
        `TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns one of two numeric values determined by a logical test.~PARAMETER_LIST=Logical Expression, Numeric Expression, N` &&
        `umeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns one of two set values determined by a logical test.~PARAMETER_LIST=Logical Expression, Set, Set~RETURN_TYPE=12~O` &&
        `RIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IIf~DESCRIPTION=Returns one of two string values determined by a logical test.~PARAMETER_LIST=Logical Expression, String, String~RETURN_` &&
        `TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=IIf` TO result.
    APPEND `FUNCTION_NAME=IN~PARAMETER_LIST=Member, Set~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IN` TO result.
    APPEND `FUNCTION_NAME=InStr~DESCRIPTION=Returns the position of an occurrence of one string within another.~PARAMETER_LIST=Integer, String, String, Integer~RE` &&
        `TURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=InStr` TO result.
    APPEND `FUNCTION_NAME=InStr~DESCRIPTION=Returns the position of an occurrence of one string within another.~PARAMETER_LIST=Integer, String, String~RETURN_TYPE` &&
        `=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=InStr` TO result.
    APPEND `FUNCTION_NAME=InStr~DESCRIPTION=Returns a Variant (Long) specifying the position of the first occurrence of one string within another.~PARAMETER_LIST=` &&
        `String, String~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=InStr` TO result.
    APPEND `FUNCTION_NAME=InStrRev~DESCRIPTION=Returns the position of an occurrence of one string within another, from the end of string.~PARAMETER_LIST=String, ` &&
        `String, Integer, Integer~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=InStrRev` TO result.
    APPEND `FUNCTION_NAME=InStrRev~DESCRIPTION=Returns the position of an occurrence of one string within another, from the end of string.~PARAMETER_LIST=String, ` &&
        `String, Integer~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=InStrRev` TO result.
    APPEND `FUNCTION_NAME=InStrRev~DESCRIPTION=Returns the position of an occurrence of one string within another, from the end of string.~PARAMETER_LIST=String, ` &&
        `String~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=InStrRev` TO result.
    APPEND `FUNCTION_NAME=Int~DESCRIPTION=Returns the integer portion of a number. If negative, returns the negative number less than or equal to the number.~PARA` &&
        `METER_LIST=Value~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Int` TO result.
    APPEND `FUNCTION_NAME=Intersect~DESCRIPTION=Returns the intersection of two input sets, optionally retaining duplicates.~PARAMETER_LIST=Set, Set, Symbol~RETUR` &&
        `N_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Intersect` TO result.
    APPEND `FUNCTION_NAME=Intersect~DESCRIPTION=Returns the intersection of two input sets, optionally retaining duplicates.~PARAMETER_LIST=Set, Set~RETURN_TYPE=1` &&
        `2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Intersect` TO result.
    APPEND `FUNCTION_NAME=InverseNormal~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=InverseNormal` TO result.
    APPEND `FUNCTION_NAME=IPmt~DESCRIPTION=Returns a Double specifying the interest payment for a given period of an annuity based on periodic, fixed payments and` &&
        ` a fixed interest rate.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Logical Exp` &&
        `ression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=IPmt` TO result.
    APPEND `FUNCTION_NAME=IPmt~DESCRIPTION=Returns a Double specifying the interest payment for a given period of an annuity based on periodic, fixed payments and` &&
        ` a fixed interest rate.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression~RETURN_TYPE=` &&
        `5~ORIGIN=1~INTERFACE_NAME=~CAPTION=IPmt` TO result.
    APPEND `FUNCTION_NAME=IPmt~DESCRIPTION=Returns a Double specifying the interest payment for a given period of an annuity based on periodic, fixed payments and` &&
        ` a fixed interest rate.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE` &&
        `_NAME=~CAPTION=IPmt` TO result.
    APPEND `FUNCTION_NAME=IRR~DESCRIPTION=Returns a Double specifying the internal rate of return for a series of periodic cash flows (payments and receipts).~PAR` &&
        `AMETER_LIST=Array, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=IRR` TO result.
    APPEND `FUNCTION_NAME=IRR~DESCRIPTION=Returns a Double specifying the internal rate of return for a series of periodic cash flows (payments and receipts).~PAR` &&
        `AMETER_LIST=Array~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=IRR` TO result.
    APPEND `FUNCTION_NAME=IS~DESCRIPTION=Returns whether two objects are the same~PARAMETER_LIST=Member, Member~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IS` TO result.
    APPEND `FUNCTION_NAME=IS~DESCRIPTION=Returns whether two objects are the same~PARAMETER_LIST=Level, Level~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IS` TO result.
    APPEND `FUNCTION_NAME=IS~DESCRIPTION=Returns whether two objects are the same~PARAMETER_LIST=Hierarchy, Hierarchy~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPT` &&
        `ION=IS` TO result.
    APPEND `FUNCTION_NAME=IS~DESCRIPTION=Returns whether two objects are the same~PARAMETER_LIST=Dimension, Dimension~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPT` &&
        `ION=IS` TO result.
    APPEND `FUNCTION_NAME=IS~DESCRIPTION=Returns whether two objects are the same~PARAMETER_LIST=Tuple, Tuple~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IS` TO result.
    APPEND `FUNCTION_NAME=IS EMPTY~DESCRIPTION=Determines if an expression evaluates to the empty cell value.~PARAMETER_LIST=Member~RETURN_TYPE=11~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=IS EMPTY` TO result.
    APPEND `FUNCTION_NAME=IS EMPTY~DESCRIPTION=Determines if an expression evaluates to the empty cell value.~PARAMETER_LIST=Tuple~RETURN_TYPE=11~ORIGIN=1~INTERFA` &&
        `CE_NAME=~CAPTION=IS EMPTY` TO result.
    APPEND `FUNCTION_NAME=IS NULL~DESCRIPTION=Returns whether an object is null~PARAMETER_LIST=Member~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IS NULL` TO result.
    APPEND `FUNCTION_NAME=IS NULL~DESCRIPTION=Returns whether an object is null~PARAMETER_LIST=Level~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IS NULL` TO result.
    APPEND `FUNCTION_NAME=IS NULL~DESCRIPTION=Returns whether an object is null~PARAMETER_LIST=Hierarchy~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IS NULL` TO result.
    APPEND `FUNCTION_NAME=IS NULL~DESCRIPTION=Returns whether an object is null~PARAMETER_LIST=Dimension~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IS NULL` TO result.
    APPEND `FUNCTION_NAME=IsDate~DESCRIPTION=Returns a Boolean value indicating whether an expression can be converted to a date.~PARAMETER_LIST=Value~RETURN_TYPE` &&
        `=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=IsDate` TO result.
    APPEND `FUNCTION_NAME=IsEmpty~DESCRIPTION=Determines if an expression evaluates to the empty cell value.~PARAMETER_LIST=String~RETURN_TYPE=11~ORIGIN=1~INTERFA` &&
        `CE_NAME=~CAPTION=IsEmpty` TO result.
    APPEND `FUNCTION_NAME=IsEmpty~DESCRIPTION=Determines if an expression evaluates to the empty cell value.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=11~ORIG` &&
        `IN=1~INTERFACE_NAME=~CAPTION=IsEmpty` TO result.
    APPEND `FUNCTION_NAME=Item~DESCRIPTION=Returns a member from the tuple specified in <Tuple>. The member to be returned is specified by the zero-based position` &&
        ` of the member in the set in <Index>.~PARAMETER_LIST=Tuple, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Item` TO result.
    APPEND `FUNCTION_NAME=Item~DESCRIPTION=Returns a tuple from the set specified in <Set>. The tuple to be returned is specified by the zero-based position of th` &&
        `e tuple in the set in <Index>.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Item` TO result.
    APPEND `FUNCTION_NAME=Item~DESCRIPTION=Returns a tuple from the set specified in <Set>. The tuple to be returned is specified by the member name (or names) in` &&
        ` <String>.~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=Item` TO result.
    APPEND `FUNCTION_NAME=Lag~DESCRIPTION=Returns a member further along the specified member's dimension.~PARAMETER_LIST=Member, Numeric Expression~RETURN_TYPE=1` &&
        `2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Lag` TO result.
    APPEND `FUNCTION_NAME=LastChild~DESCRIPTION=Returns the last child of a member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=LastChil` &&
        `d` TO result.
    APPEND `FUNCTION_NAME=LastNonEmpty~PARAMETER_LIST=Set, Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=LastNonEmpty` TO result.
    APPEND `FUNCTION_NAME=LastPeriods~DESCRIPTION=Returns a set of members prior to and including a specified member.~PARAMETER_LIST=Numeric Expression~RETURN_TYP` &&
        `E=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=LastPeriods` TO result.
    APPEND `FUNCTION_NAME=LastPeriods~DESCRIPTION=Returns a set of members prior to and including a specified member.~PARAMETER_LIST=Numeric Expression, Member~RE` &&
        `TURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=LastPeriods` TO result.
    APPEND `FUNCTION_NAME=LastSibling~DESCRIPTION=Returns the last child of the parent of a member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~` &&
        `CAPTION=LastSibling` TO result.
    APPEND `FUNCTION_NAME=LCase~DESCRIPTION=Returns a String that has been converted to lowercase.~PARAMETER_LIST=String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CA` &&
        `PTION=LCase` TO result.
    APPEND `FUNCTION_NAME=Lead~DESCRIPTION=Returns a member further along the specified member's dimension.~PARAMETER_LIST=Member, Numeric Expression~RETURN_TYPE=` &&
        `12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Lead` TO result.
    APPEND `FUNCTION_NAME=Left~DESCRIPTION=Returns a specified number of characters from the left side of a string.~PARAMETER_LIST=String, Integer~RETURN_TYPE=8~O` &&
        `RIGIN=1~INTERFACE_NAME=~CAPTION=Left` TO result.
    APPEND `FUNCTION_NAME=Len~DESCRIPTION=Returns the number of characters in a string~PARAMETER_LIST=String~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Len` TO result.
    APPEND `FUNCTION_NAME=Level~DESCRIPTION=Returns a member's level.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Level` TO result.
    APPEND `FUNCTION_NAME=Level_Number~DESCRIPTION=Returns the level number of a member.~PARAMETER_LIST=Member~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Leve` &&
        `l_Number` TO result.
    APPEND `FUNCTION_NAME=Levels~DESCRIPTION=Returns the level whose position in a hierarchy is specified by a numeric expression.~PARAMETER_LIST=Hierarchy, Numer` &&
        `ic Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Levels` TO result.
    APPEND `FUNCTION_NAME=Levels~DESCRIPTION=Returns the level whose name is specified by a string expression.~PARAMETER_LIST=Hierarchy, String~RETURN_TYPE=12~ORI` &&
        `GIN=1~INTERFACE_NAME=~CAPTION=Levels` TO result.
    APPEND `FUNCTION_NAME=Levels~DESCRIPTION=Returns the level whose name is specified by a string expression.~PARAMETER_LIST=String~RETURN_TYPE=12~ORIGIN=1~INTER` &&
        `FACE_NAME=~CAPTION=Levels` TO result.
    APPEND `FUNCTION_NAME=LinRegIntercept~DESCRIPTION=Calculates the linear regression of a set and returns the value of b in the regression line y = ax + b.~PARA` &&
        `METER_LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegIntercept` TO result.
    APPEND `FUNCTION_NAME=LinRegIntercept~DESCRIPTION=Calculates the linear regression of a set and returns the value of b in the regression line y = ax + b.~PARA` &&
        `METER_LIST=Set, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegIntercept` TO result.
    APPEND `FUNCTION_NAME=LinRegPoint~DESCRIPTION=Calculates the linear regression of a set and returns the value of y in the regression line y = ax + b.~PARAMETE` &&
        `R_LIST=Numeric Expression, Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegPoint` TO result.
    APPEND `FUNCTION_NAME=LinRegPoint~DESCRIPTION=Calculates the linear regression of a set and returns the value of y in the regression line y = ax + b.~PARAMETE` &&
        `R_LIST=Numeric Expression, Set, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegPoint` TO result.
    APPEND `FUNCTION_NAME=LinRegR2~DESCRIPTION=Calculates the linear regression of a set and returns R2 (the coefficient of determination).~PARAMETER_LIST=Set, Nu` &&
        `meric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegR2` TO result.
    APPEND `FUNCTION_NAME=LinRegR2~DESCRIPTION=Calculates the linear regression of a set and returns R2 (the coefficient of determination).~PARAMETER_LIST=Set, Nu` &&
        `meric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegR2` TO result.
    APPEND `FUNCTION_NAME=LinRegSlope~DESCRIPTION=Calculates the linear regression of a set and returns the value of a in the regression line y = ax + b.~PARAMETE` &&
        `R_LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegSlope` TO result.
    APPEND `FUNCTION_NAME=LinRegSlope~DESCRIPTION=Calculates the linear regression of a set and returns the value of a in the regression line y = ax + b.~PARAMETE` &&
        `R_LIST=Set, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegSlope` TO result.
    APPEND `FUNCTION_NAME=LinRegVariance~DESCRIPTION=Calculates the linear regression of a set and returns the variance associated with the regression line y = ax` &&
        ` + b.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegVariance` TO result.
    APPEND `FUNCTION_NAME=LinRegVariance~DESCRIPTION=Calculates the linear regression of a set and returns the variance associated with the regression line y = ax` &&
        ` + b.~PARAMETER_LIST=Set, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=LinRegVariance` TO result.
    APPEND `FUNCTION_NAME=Log~DESCRIPTION=Returns a Double specifying the natural logarithm of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~` &&
        `INTERFACE_NAME=~CAPTION=Log` TO result.
    APPEND `FUNCTION_NAME=Log10~DESCRIPTION=Returns the base-10 logarithm of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CA` &&
        `PTION=Log10` TO result.
    APPEND `FUNCTION_NAME=LTrim~DESCRIPTION=Returns a Variant (String) containing a copy of a specified string without leading spaces.~PARAMETER_LIST=String~RETUR` &&
        `N_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=LTrim` TO result.
    APPEND `FUNCTION_NAME=MATCHES~PARAMETER_LIST=String, String~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=MATCHES` TO result.
    APPEND `FUNCTION_NAME=Max~DESCRIPTION=Returns the maximum value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=Max` TO result.
    APPEND `FUNCTION_NAME=Max~DESCRIPTION=Returns the maximum value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TY` &&
        `PE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Max` TO result.
    APPEND `FUNCTION_NAME=Median~DESCRIPTION=Returns the median value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTE` &&
        `RFACE_NAME=~CAPTION=Median` TO result.
    APPEND `FUNCTION_NAME=Median~DESCRIPTION=Returns the median value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_` &&
        `TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Median` TO result.
    APPEND `FUNCTION_NAME=Member_Caption~DESCRIPTION=Returns the caption of a member.~PARAMETER_LIST=Member~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Member_` &&
        `Caption` TO result.
    APPEND `FUNCTION_NAME=Members~DESCRIPTION=Returns the set of members in a hierarchy.~PARAMETER_LIST=Hierarchy~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=` &&
        `Members` TO result.
    APPEND `FUNCTION_NAME=Members~DESCRIPTION=Returns the set of members in a level.~PARAMETER_LIST=Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Members` TO result.
    APPEND `FUNCTION_NAME=Members~DESCRIPTION=Returns the member whose name is specified by a string expression.~PARAMETER_LIST=String~RETURN_TYPE=12~ORIGIN=1~INT` &&
        `ERFACE_NAME=~CAPTION=Members` TO result.
    APPEND `FUNCTION_NAME=Mid~DESCRIPTION=Returns a specified number of characters from a string.~PARAMETER_LIST=String, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~I` &&
        `NTERFACE_NAME=~CAPTION=Mid` TO result.
    APPEND `FUNCTION_NAME=Mid~DESCRIPTION=Returns a specified number of characters from a string.~PARAMETER_LIST=String, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_` &&
        `NAME=~CAPTION=Mid` TO result.
    APPEND `FUNCTION_NAME=Min~DESCRIPTION=Returns the minimum value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=Min` TO result.
    APPEND `FUNCTION_NAME=Min~DESCRIPTION=Returns the minimum value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TY` &&
        `PE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Min` TO result.
    APPEND `FUNCTION_NAME=Minute~DESCRIPTION=Returns a Variant (Integer) specifying a whole number between 0 and 59, inclusive, representing the minute of the hou` &&
        `r.~PARAMETER_LIST=DateTime~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Minute` TO result.
    APPEND `FUNCTION_NAME=MIRR~DESCRIPTION=Returns a Double specifying the modified internal rate of return for a series of periodic cash flows (payments and rece` &&
        `ipts).~PARAMETER_LIST=Array, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=MIRR` TO result.
    APPEND `FUNCTION_NAME=Mod~DESCRIPTION=Returns the remainder of dividing n by d.~PARAMETER_LIST=Value, Value~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Mod` TO result.
    APPEND `FUNCTION_NAME=Month~DESCRIPTION=Returns a Variant (Integer) specifying a whole number between 1 and 12, inclusive, representing the month of the year.` &&
        `~PARAMETER_LIST=DateTime~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Month` TO result.
    APPEND `FUNCTION_NAME=MonthName~DESCRIPTION=Returns a string indicating the specified month.~PARAMETER_LIST=Integer, Logical Expression~RETURN_TYPE=8~ORIGIN=1` &&
        `~INTERFACE_NAME=~CAPTION=MonthName` TO result.
    APPEND `FUNCTION_NAME=Mtd~DESCRIPTION=A shortcut function for the PeriodsToDate function that specifies the level to be Month.~PARAMETER_LIST=~RETURN_TYPE=12~` &&
        `ORIGIN=1~INTERFACE_NAME=~CAPTION=Mtd` TO result.
    APPEND `FUNCTION_NAME=Mtd~DESCRIPTION=A shortcut function for the PeriodsToDate function that specifies the level to be Month.~PARAMETER_LIST=Member~RETURN_TY` &&
        `PE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Mtd` TO result.
    APPEND `FUNCTION_NAME=Name~DESCRIPTION=Returns the name of a dimension.~PARAMETER_LIST=Dimension~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Name` TO result.
    APPEND `FUNCTION_NAME=Name~DESCRIPTION=Returns the name of a hierarchy.~PARAMETER_LIST=Hierarchy~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Name` TO result.
    APPEND `FUNCTION_NAME=Name~DESCRIPTION=Returns the name of a level.~PARAMETER_LIST=Level~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Name` TO result.
    APPEND `FUNCTION_NAME=Name~DESCRIPTION=Returns the name of a member.~PARAMETER_LIST=Member~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Name` TO result.
    APPEND `FUNCTION_NAME=NativizeSet~DESCRIPTION=Tries to natively evaluate <Set>.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=NativizeSet` TO result.
    APPEND `FUNCTION_NAME=NextMember~DESCRIPTION=Returns the next member in the level that contains a specified member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGI` &&
        `N=1~INTERFACE_NAME=~CAPTION=NextMember` TO result.
    APPEND `FUNCTION_NAME=NonEmpty~DESCRIPTION=Returns the set of tuples that are not empty from a specified set, based on the cross product of the specified set ` &&
        `with a second set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=NonEmpty` TO result.
    APPEND `FUNCTION_NAME=NonEmpty~DESCRIPTION=Returns the set of tuples that are not empty from a specified set, based on the cross product of the specified set ` &&
        `with a second set.~PARAMETER_LIST=Set, Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=NonEmpty` TO result.
    APPEND `FUNCTION_NAME=NonEmptyCrossJoin~DESCRIPTION=Returns the cross product of two sets, excluding empty tuples and tuples without associated fact table dat` &&
        `a.~PARAMETER_LIST=Set, Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=NonEmptyCrossJoin` TO result.
    APPEND `FUNCTION_NAME=NOT~DESCRIPTION=Returns the negation of a condition.~PARAMETER_LIST=Logical Expression~RETURN_TYPE=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=N` &&
        `OT` TO result.
    APPEND `FUNCTION_NAME=Now~DESCRIPTION=Returns a Variant (Date) specifying the current date and time according your computer's system date and time.~PARAMETER_` &&
        `LIST=~RETURN_TYPE=7~ORIGIN=1~INTERFACE_NAME=~CAPTION=Now` TO result.
    APPEND `FUNCTION_NAME=NPer~DESCRIPTION=Returns a Double specifying the number of periods for an annuity based on periodic, fixed payments and a fixed interest` &&
        ` rate.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Logical Expression~RETURN_TYPE=5~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=NPer` TO result.
    APPEND `FUNCTION_NAME=NPV~DESCRIPTION=Returns a Double specifying the net present value of an investment based on a series of periodic cash flows (payments an` &&
        `d receipts) and a discount rate.~PARAMETER_LIST=Numeric Expression, Array~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=NPV` TO result.
    APPEND `FUNCTION_NAME=NullValue~PARAMETER_LIST=~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=NullValue` TO result.
    APPEND `FUNCTION_NAME=Oct~DESCRIPTION=Returns a Variant (String) representing the octal value of a number.~PARAMETER_LIST=Value~RETURN_TYPE=8~ORIGIN=1~INTERFA` &&
        `CE_NAME=~CAPTION=Oct` TO result.
    APPEND `FUNCTION_NAME=OpeningPeriod~DESCRIPTION=Returns the first descendant of a member at a level.~PARAMETER_LIST=~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~C` &&
        `APTION=OpeningPeriod` TO result.
    APPEND `FUNCTION_NAME=OpeningPeriod~DESCRIPTION=Returns the first descendant of a member at a level.~PARAMETER_LIST=Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NA` &&
        `ME=~CAPTION=OpeningPeriod` TO result.
    APPEND `FUNCTION_NAME=OpeningPeriod~DESCRIPTION=Returns the first descendant of a member at a level.~PARAMETER_LIST=Level, Member~RETURN_TYPE=12~ORIGIN=1~INTE` &&
        `RFACE_NAME=~CAPTION=OpeningPeriod` TO result.
    APPEND `FUNCTION_NAME=OR~DESCRIPTION=Returns the disjunction of two conditions.~PARAMETER_LIST=Logical Expression, Logical Expression~RETURN_TYPE=11~ORIGIN=1~` &&
        `INTERFACE_NAME=~CAPTION=OR` TO result.
    APPEND `FUNCTION_NAME=Order~DESCRIPTION=Arranges members of a set, optionally preserving or breaking the hierarchy.~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN` &&
        `=1~INTERFACE_NAME=~CAPTION=Order` TO result.
    APPEND `FUNCTION_NAME=OrderKey~DESCRIPTION=Returns the member order key.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=OrderKey` TO result.
    APPEND `FUNCTION_NAME=Ordinal~DESCRIPTION=Returns the zero-based ordinal value associated with a level.~PARAMETER_LIST=Level~RETURN_TYPE=5~ORIGIN=1~INTERFACE_` &&
        `NAME=~CAPTION=Ordinal` TO result.
    APPEND `FUNCTION_NAME=ParallelPeriod~DESCRIPTION=Returns a member from a prior period in the same relative position as a specified member.~PARAMETER_LIST=~RET` &&
        `URN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=ParallelPeriod` TO result.
    APPEND `FUNCTION_NAME=ParallelPeriod~DESCRIPTION=Returns a member from a prior period in the same relative position as a specified member.~PARAMETER_LIST=Leve` &&
        `l~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=ParallelPeriod` TO result.
    APPEND `FUNCTION_NAME=ParallelPeriod~DESCRIPTION=Returns a member from a prior period in the same relative position as a specified member.~PARAMETER_LIST=Leve` &&
        `l, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=ParallelPeriod` TO result.
    APPEND `FUNCTION_NAME=ParallelPeriod~DESCRIPTION=Returns a member from a prior period in the same relative position as a specified member.~PARAMETER_LIST=Leve` &&
        `l, Numeric Expression, Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=ParallelPeriod` TO result.
    APPEND `FUNCTION_NAME=Parameter~DESCRIPTION=Returns default value of parameter.~PARAMETER_LIST=String, Symbol, String, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE` &&
        `_NAME=~CAPTION=Parameter` TO result.
    APPEND `FUNCTION_NAME=Parameter~DESCRIPTION=Returns default value of parameter.~PARAMETER_LIST=String, Symbol, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~C` &&
        `APTION=Parameter` TO result.
    APPEND `FUNCTION_NAME=Parameter~DESCRIPTION=Returns default value of parameter.~PARAMETER_LIST=String, Symbol, Numeric Expression, String~RETURN_TYPE=5~ORIGIN` &&
        `=1~INTERFACE_NAME=~CAPTION=Parameter` TO result.
    APPEND `FUNCTION_NAME=Parameter~DESCRIPTION=Returns default value of parameter.~PARAMETER_LIST=String, Symbol, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTER` &&
        `FACE_NAME=~CAPTION=Parameter` TO result.
    APPEND `FUNCTION_NAME=Parameter~DESCRIPTION=Returns default value of parameter.~PARAMETER_LIST=String, Hierarchy, Member, String~RETURN_TYPE=12~ORIGIN=1~INTER` &&
        `FACE_NAME=~CAPTION=Parameter` TO result.
    APPEND `FUNCTION_NAME=Parameter~DESCRIPTION=Returns default value of parameter.~PARAMETER_LIST=String, Hierarchy, Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAM` &&
        `E=~CAPTION=Parameter` TO result.
    APPEND `FUNCTION_NAME=Parameter~DESCRIPTION=Returns default value of parameter.~PARAMETER_LIST=String, Hierarchy, Set, String~RETURN_TYPE=12~ORIGIN=1~INTERFAC` &&
        `E_NAME=~CAPTION=Parameter` TO result.
    APPEND `FUNCTION_NAME=Parameter~DESCRIPTION=Returns default value of parameter.~PARAMETER_LIST=String, Hierarchy, Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~` &&
        `CAPTION=Parameter` TO result.
    APPEND `FUNCTION_NAME=ParamRef~DESCRIPTION=Returns the current value of this parameter. If it is null, returns the default value.~PARAMETER_LIST=String~RETURN` &&
        `_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=ParamRef` TO result.
    APPEND `FUNCTION_NAME=Parent~DESCRIPTION=Returns the parent of a member.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Parent` TO result.
    APPEND `FUNCTION_NAME=Percentile~DESCRIPTION=Returns the value of the tuple that is at a given percentile of a set.~PARAMETER_LIST=Set, Numeric Expression, Nu` &&
        `meric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Percentile` TO result.
    APPEND `FUNCTION_NAME=PeriodsToDate~DESCRIPTION=Returns a set of periods (members) from a specified level starting with the first period and ending with a spe` &&
        `cified member.~PARAMETER_LIST=~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=PeriodsToDate` TO result.
    APPEND `FUNCTION_NAME=PeriodsToDate~DESCRIPTION=Returns a set of periods (members) from a specified level starting with the first period and ending with a spe` &&
        `cified member.~PARAMETER_LIST=Level~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=PeriodsToDate` TO result.
    APPEND `FUNCTION_NAME=PeriodsToDate~DESCRIPTION=Returns a set of periods (members) from a specified level starting with the first period and ending with a spe` &&
        `cified member.~PARAMETER_LIST=Level, Member~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=PeriodsToDate` TO result.
    APPEND `FUNCTION_NAME=Pi~DESCRIPTION=Returns the number 3.14159265358979, the mathematical constant pi, accurate to 15 digits.~PARAMETER_LIST=~RETURN_TYPE=5~O` &&
        `RIGIN=1~INTERFACE_NAME=~CAPTION=Pi` TO result.
    APPEND `FUNCTION_NAME=Pmt~DESCRIPTION=Returns a Double specifying the payment for an annuity based on periodic, fixed payments and a fixed interest rate.~PARA` &&
        `METER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Logical Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~C` &&
        `APTION=Pmt` TO result.
    APPEND `FUNCTION_NAME=Power~DESCRIPTION=Returns the result of a number raised to a power.~PARAMETER_LIST=Numeric Expression, Numeric Expression~RETURN_TYPE=5~` &&
        `ORIGIN=1~INTERFACE_NAME=~CAPTION=Power` TO result.
    APPEND `FUNCTION_NAME=PPmt~DESCRIPTION=Returns a Double specifying the principal payment for a given period of an annuity based on periodic, fixed payments an` &&
        `d a fixed interest rate.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Logical Ex` &&
        `pression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=PPmt` TO result.
    APPEND `FUNCTION_NAME=PPmt~DESCRIPTION=Returns a Double specifying the principal payment for a given period of an annuity based on periodic, fixed payments an` &&
        `d a fixed interest rate.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression~RETURN_TYPE` &&
        `=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=PPmt` TO result.
    APPEND `FUNCTION_NAME=PPmt~DESCRIPTION=Returns a Double specifying the principal payment for a given period of an annuity based on periodic, fixed payments an` &&
        `d a fixed interest rate.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFAC` &&
        `E_NAME=~CAPTION=PPmt` TO result.
    APPEND `FUNCTION_NAME=PrevMember~DESCRIPTION=Returns the previous member in the level that contains a specified member.~PARAMETER_LIST=Member~RETURN_TYPE=12~O` &&
        `RIGIN=1~INTERFACE_NAME=~CAPTION=PrevMember` TO result.
    APPEND `FUNCTION_NAME=Properties~DESCRIPTION=Returns the value of a member property.~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION=Prop` &&
        `erties` TO result.
    APPEND `FUNCTION_NAME=PV~DESCRIPTION=Returns a Double specifying the present value of an annuity based on periodic, fixed payments to be paid in the future an` &&
        `d a fixed interest rate.~PARAMETER_LIST=Numeric Expression, Numeric Expression, Numeric Expression, Numeric Expression, Logical Expression~RETURN_TYPE` &&
        `=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=PV` TO result.
    APPEND `FUNCTION_NAME=Qtd~DESCRIPTION=A shortcut function for the PeriodsToDate function that specifies the level to be Quarter.~PARAMETER_LIST=~RETURN_TYPE=1` &&
        `2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Qtd` TO result.
    APPEND `FUNCTION_NAME=Qtd~DESCRIPTION=A shortcut function for the PeriodsToDate function that specifies the level to be Quarter.~PARAMETER_LIST=Member~RETURN_` &&
        `TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Qtd` TO result.
    APPEND `FUNCTION_NAME=Radians~DESCRIPTION=Converts degrees to radians.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Radian` &&
        `s` TO result.
    APPEND `FUNCTION_NAME=Rank~DESCRIPTION=Returns the one-based rank of a tuple in a set.~PARAMETER_LIST=Tuple, Set~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTIO` &&
        `N=Rank` TO result.
    APPEND `FUNCTION_NAME=Rank~DESCRIPTION=Returns the one-based rank of a tuple in a set.~PARAMETER_LIST=Tuple, Set, Numeric Expression~RETURN_TYPE=2~ORIGIN=1~IN` &&
        `TERFACE_NAME=~CAPTION=Rank` TO result.
    APPEND `FUNCTION_NAME=Rank~DESCRIPTION=Returns the one-based rank of a tuple in a set.~PARAMETER_LIST=Member, Set~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTI` &&
        `ON=Rank` TO result.
    APPEND `FUNCTION_NAME=Rank~DESCRIPTION=Returns the one-based rank of a tuple in a set.~PARAMETER_LIST=Member, Set, Numeric Expression~RETURN_TYPE=2~ORIGIN=1~I` &&
        `NTERFACE_NAME=~CAPTION=Rank` TO result.
    APPEND `FUNCTION_NAME=Rate~DESCRIPTION=Returns a Double specifying the interest rate per period for an annuity.~PARAMETER_LIST=Numeric Expression, Numeric Exp` &&
        `ression, Numeric Expression, Numeric Expression, Logical Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Rate` TO result.
    APPEND `FUNCTION_NAME=Rate~DESCRIPTION=Returns a Double specifying the interest rate per period for an annuity.~PARAMETER_LIST=Numeric Expression, Numeric Exp` &&
        `ression, Numeric Expression, Numeric Expression, Logical Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Rate` TO result.
    APPEND `FUNCTION_NAME=Rate~DESCRIPTION=Returns a Double specifying the interest rate per period for an annuity.~PARAMETER_LIST=Numeric Expression, Numeric Exp` &&
        `ression, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Rate` TO result.
    APPEND `FUNCTION_NAME=Rate~DESCRIPTION=Returns a Double specifying the interest rate per period for an annuity.~PARAMETER_LIST=Numeric Expression, Numeric Exp` &&
        `ression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Rate` TO result.
    APPEND `FUNCTION_NAME=Replace~DESCRIPTION=Returns a string in which a specified substring has been replaced with another substring a specified number of times` &&
        `.~PARAMETER_LIST=String, String, String, Integer, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Replace` TO result.
    APPEND `FUNCTION_NAME=Replace~DESCRIPTION=Returns a string in which a specified substring has been replaced with another substring a specified number of times` &&
        `.~PARAMETER_LIST=String, String, String, Integer, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Replace` TO result.
    APPEND `FUNCTION_NAME=Replace~DESCRIPTION=Returns a string in which a specified substring has been replaced with another substring a specified number of times` &&
        `.~PARAMETER_LIST=String, String, String, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Replace` TO result.
    APPEND `FUNCTION_NAME=Replace~DESCRIPTION=~PARAMETER_LIST=String, String, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Replace` TO result.
    APPEND `FUNCTION_NAME=Right~DESCRIPTION=Returns a Variant (String) containing a specified number of characters from the right side of a string.~PARAMETER_LIST` &&
        `=String, Integer~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Right` TO result.
    APPEND `FUNCTION_NAME=Round~DESCRIPTION=Returns a number rounded to a specified number of decimal places.~PARAMETER_LIST=Numeric Expression, Integer~RETURN_TY` &&
        `PE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Round` TO result.
    APPEND `FUNCTION_NAME=Round~DESCRIPTION=Returns a number rounded to a specified number of decimal places.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIG` &&
        `IN=1~INTERFACE_NAME=~CAPTION=Round` TO result.
    APPEND `FUNCTION_NAME=RTrim~DESCRIPTION=Returns a Variant (String) containing a copy of a specified string without trailing spaces.~PARAMETER_LIST=String~RETU` &&
        `RN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=RTrim` TO result.
    APPEND `FUNCTION_NAME=Second~DESCRIPTION=Returns a Variant (Integer) specifying a whole number between 0 and 59, inclusive, representing the second of the min` &&
        `ute.~PARAMETER_LIST=DateTime~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Second` TO result.
    APPEND `FUNCTION_NAME=SetToStr~DESCRIPTION=Constructs a string from a set.~PARAMETER_LIST=Set~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=SetToStr` TO result.
    APPEND `FUNCTION_NAME=Sgn~DESCRIPTION=Returns a Variant (Integer) indicating the sign of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=2~ORIGIN=1~IN` &&
        `TERFACE_NAME=~CAPTION=Sgn` TO result.
    APPEND `FUNCTION_NAME=Siblings~DESCRIPTION=Returns the siblings of a specified member, including the member itself.~PARAMETER_LIST=Member~RETURN_TYPE=12~ORIGI` &&
        `N=1~INTERFACE_NAME=~CAPTION=Siblings` TO result.
    APPEND `FUNCTION_NAME=Sin~DESCRIPTION=Returns a Double specifying the sine of an angle.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAM` &&
        `E=~CAPTION=Sin` TO result.
    APPEND `FUNCTION_NAME=Sinh~DESCRIPTION=Returns the hyperbolic sine of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTI` &&
        `ON=Sinh` TO result.
    APPEND `FUNCTION_NAME=SLN~DESCRIPTION=Returns a Double specifying the straight-line depreciation of an asset for a single period.~PARAMETER_LIST=Numeric Expre` &&
        `ssion, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=SLN` TO result.
    APPEND `FUNCTION_NAME=Space~DESCRIPTION=Returns a Variant (String) consisting of the specified number of spaces.~PARAMETER_LIST=Integer~RETURN_TYPE=8~ORIGIN=1` &&
        `~INTERFACE_NAME=~CAPTION=Space` TO result.
    APPEND `FUNCTION_NAME=Sqr~DESCRIPTION=Returns a Double specifying the square root of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=Sqr` TO result.
    APPEND `FUNCTION_NAME=SqrtPi~DESCRIPTION=Returns the square root of (number * pi).~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CA` &&
        `PTION=SqrtPi` TO result.
    APPEND `FUNCTION_NAME=Stddev~DESCRIPTION=Alias for Stdev.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Stddev` TO result.
    APPEND `FUNCTION_NAME=Stddev~DESCRIPTION=Alias for Stdev.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Stddev` TO result.
    APPEND `FUNCTION_NAME=StddevP~DESCRIPTION=Alias for StdevP.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=StddevP` TO result.
    APPEND `FUNCTION_NAME=StddevP~DESCRIPTION=Alias for StdevP.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=StddevP` TO result.
    APPEND `FUNCTION_NAME=Stdev~DESCRIPTION=Returns the standard deviation of a numeric expression evaluated over a set (unbiased).~PARAMETER_LIST=Set~RETURN_TYPE` &&
        `=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Stdev` TO result.
    APPEND `FUNCTION_NAME=Stdev~DESCRIPTION=Returns the standard deviation of a numeric expression evaluated over a set (unbiased).~PARAMETER_LIST=Set, Numeric Ex` &&
        `pression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Stdev` TO result.
    APPEND `FUNCTION_NAME=StdevP~DESCRIPTION=Returns the standard deviation of a numeric expression evaluated over a set (biased).~PARAMETER_LIST=Set~RETURN_TYPE=` &&
        `5~ORIGIN=1~INTERFACE_NAME=~CAPTION=StdevP` TO result.
    APPEND `FUNCTION_NAME=StdevP~DESCRIPTION=Returns the standard deviation of a numeric expression evaluated over a set (biased).~PARAMETER_LIST=Set, Numeric Exp` &&
        `ression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=StdevP` TO result.
    APPEND `FUNCTION_NAME=Str~DESCRIPTION=Returns a Variant (String) representation of a number.~PARAMETER_LIST=Value~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTI` &&
        `ON=Str` TO result.
    APPEND `FUNCTION_NAME=StrComp~DESCRIPTION=Returns a Variant (Integer) indicating the result of a string comparison.~PARAMETER_LIST=String, String, Integer~RET` &&
        `URN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=StrComp` TO result.
    APPEND `FUNCTION_NAME=StrComp~DESCRIPTION=Returns a Variant (Integer) indicating the result of a string comparison.~PARAMETER_LIST=String, String~RETURN_TYPE=` &&
        `2~ORIGIN=1~INTERFACE_NAME=~CAPTION=StrComp` TO result.
    APPEND `FUNCTION_NAME=String~DESCRIPTION=~PARAMETER_LIST=Integer, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=String` TO result.
    APPEND `FUNCTION_NAME=StripCalculatedMembers~DESCRIPTION=Removes calculated members from a set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAP` &&
        `TION=StripCalculatedMembers` TO result.
    APPEND `FUNCTION_NAME=StrReverse~DESCRIPTION=Returns a string in which the character order of a specified string is reversed.~PARAMETER_LIST=String~RETURN_TYP` &&
        `E=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=StrReverse` TO result.
    APPEND `FUNCTION_NAME=StrToMember~DESCRIPTION=Returns a member from a unique name String in MDX format.~PARAMETER_LIST=String~RETURN_TYPE=12~ORIGIN=1~INTERFAC` &&
        `E_NAME=~CAPTION=StrToMember` TO result.
    APPEND `FUNCTION_NAME=StrToSet~DESCRIPTION=Constructs a set from a string expression.~PARAMETER_LIST=String~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=St` &&
        `rToSet` TO result.
    APPEND `FUNCTION_NAME=StrToTuple~DESCRIPTION=Constructs a tuple from a string.~PARAMETER_LIST=String~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=StrToTupl` &&
        `e` TO result.
    APPEND `FUNCTION_NAME=Subset~DESCRIPTION=Returns a subset of elements from a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAM` &&
        `E=~CAPTION=Subset` TO result.
    APPEND `FUNCTION_NAME=Subset~DESCRIPTION=Returns a subset of elements from a set.~PARAMETER_LIST=Set, Numeric Expression, Numeric Expression~RETURN_TYPE=12~OR` &&
        `IGIN=1~INTERFACE_NAME=~CAPTION=Subset` TO result.
    APPEND `FUNCTION_NAME=Sum~DESCRIPTION=Returns the sum of a numeric expression evaluated over a set.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~` &&
        `CAPTION=Sum` TO result.
    APPEND `FUNCTION_NAME=Sum~DESCRIPTION=Returns the sum of a numeric expression evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGI` &&
        `N=1~INTERFACE_NAME=~CAPTION=Sum` TO result.
    APPEND `FUNCTION_NAME=SYD~DESCRIPTION=Returns a Double specifying the sum-of-years' digits depreciation of an asset for a specified period.~PARAMETER_LIST=Num` &&
        `eric Expression, Numeric Expression, Numeric Expression, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=SYD` TO result.
    APPEND `FUNCTION_NAME=Tail~DESCRIPTION=Returns a subset from the end of a set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Tail` TO result.
    APPEND `FUNCTION_NAME=Tail~DESCRIPTION=Returns a subset from the end of a set.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~` &&
        `CAPTION=Tail` TO result.
    APPEND `FUNCTION_NAME=Tan~DESCRIPTION=Returns a Double specifying the tangent of an angle.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_` &&
        `NAME=~CAPTION=Tan` TO result.
    APPEND `FUNCTION_NAME=Tanh~DESCRIPTION=Returns the hyperbolic tangent of a number.~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CA` &&
        `PTION=Tanh` TO result.
    APPEND `FUNCTION_NAME=ThirdQ~DESCRIPTION=Returns the 3rd quartile value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=` &&
        `1~INTERFACE_NAME=~CAPTION=ThirdQ` TO result.
    APPEND `FUNCTION_NAME=ThirdQ~DESCRIPTION=Returns the 3rd quartile value of a numeric expression evaluated over a set.~PARAMETER_LIST=Set, Numeric Expression~R` &&
        `ETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=ThirdQ` TO result.
    APPEND `FUNCTION_NAME=Time~DESCRIPTION=Returns a Variant (Date) indicating the current system time.~PARAMETER_LIST=~RETURN_TYPE=7~ORIGIN=1~INTERFACE_NAME=~CAP` &&
        `TION=Time` TO result.
    APPEND `FUNCTION_NAME=Timer~DESCRIPTION=Returns a Single representing the number of seconds elapsed since midnight.~PARAMETER_LIST=~RETURN_TYPE=5~ORIGIN=1~INT` &&
        `ERFACE_NAME=~CAPTION=Timer` TO result.
    APPEND `FUNCTION_NAME=TimeSerial~DESCRIPTION=Returns a Variant (Date) containing the time for a specific hour, minute, and second.~PARAMETER_LIST=Integer, Int` &&
        `eger, Integer~RETURN_TYPE=7~ORIGIN=1~INTERFACE_NAME=~CAPTION=TimeSerial` TO result.
    APPEND `FUNCTION_NAME=TimeValue~DESCRIPTION=Returns a Variant (Date) containing the time.~PARAMETER_LIST=DateTime~RETURN_TYPE=7~ORIGIN=1~INTERFACE_NAME=~CAPTI` &&
        `ON=TimeValue` TO result.
    APPEND `FUNCTION_NAME=ToggleDrillState~DESCRIPTION=Toggles the drill state of members. This function is a combination of DrillupMember and DrilldownMember.~PA` &&
        `RAMETER_LIST=Set, Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=ToggleDrillState` TO result.
    APPEND `FUNCTION_NAME=ToggleDrillState~DESCRIPTION=Toggles the drill state of members. This function is a combination of DrillupMember and DrilldownMember.~PA` &&
        `RAMETER_LIST=Set, Set, Symbol~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=ToggleDrillState` TO result.
    APPEND `FUNCTION_NAME=TopCount~DESCRIPTION=Returns a specified number of items from the top of a set, optionally ordering the set first.~PARAMETER_LIST=Set, N` &&
        `umeric Expression, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=TopCount` TO result.
    APPEND `FUNCTION_NAME=TopCount~DESCRIPTION=Returns a specified number of items from the top of a set, optionally ordering the set first.~PARAMETER_LIST=Set, N` &&
        `umeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=TopCount` TO result.
    APPEND `FUNCTION_NAME=TopPercent~DESCRIPTION=Sorts a set and returns the top N elements whose cumulative total is at least a specified percentage.~PARAMETER_L` &&
        `IST=Set, Numeric Expression, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=TopPercent` TO result.
    APPEND `FUNCTION_NAME=TopSum~DESCRIPTION=Sorts a set and returns the top N elements whose cumulative total is at least a specified value.~PARAMETER_LIST=Set, ` &&
        `Numeric Expression, Numeric Expression~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=TopSum` TO result.
    APPEND `FUNCTION_NAME=Trim~DESCRIPTION=Returns a Variant (String) containing a copy of a specified string without leading and trailing spaces.~PARAMETER_LIST=` &&
        `String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Trim` TO result.
    APPEND `FUNCTION_NAME=TupleToStr~DESCRIPTION=Constructs a string from a tuple.~PARAMETER_LIST=Tuple~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=TupleToStr` TO result.
    APPEND `FUNCTION_NAME=TypeName~DESCRIPTION=Returns a String that provides information about a variable.~PARAMETER_LIST=Value~RETURN_TYPE=8~ORIGIN=1~INTERFACE_` &&
        `NAME=~CAPTION=TypeName` TO result.
    APPEND `FUNCTION_NAME=UCase~DESCRIPTION=Returns a string that has been converted to uppercase~PARAMETER_LIST=String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAP` &&
        `TION=UCase` TO result.
    APPEND `FUNCTION_NAME=Union~DESCRIPTION=Returns the union of two sets, optionally retaining duplicates.~PARAMETER_LIST=Set, Set~RETURN_TYPE=12~ORIGIN=1~INTERF` &&
        `ACE_NAME=~CAPTION=Union` TO result.
    APPEND `FUNCTION_NAME=Union~DESCRIPTION=Returns the union of two sets, optionally retaining duplicates.~PARAMETER_LIST=Set, Set, Symbol~RETURN_TYPE=12~ORIGIN=` &&
        `1~INTERFACE_NAME=~CAPTION=Union` TO result.
    APPEND `FUNCTION_NAME=Unique_Name~DESCRIPTION=Returns the unique name of a member.~PARAMETER_LIST=Member~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=Unique` &&
        `_Name` TO result.
    APPEND `FUNCTION_NAME=UniqueName~DESCRIPTION=Returns the unique name of a dimension.~PARAMETER_LIST=Dimension~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=U` &&
        `niqueName` TO result.
    APPEND `FUNCTION_NAME=UniqueName~DESCRIPTION=Returns the unique name of a hierarchy.~PARAMETER_LIST=Hierarchy~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=U` &&
        `niqueName` TO result.
    APPEND `FUNCTION_NAME=UniqueName~DESCRIPTION=Returns the unique name of a level.~PARAMETER_LIST=Level~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=UniqueNam` &&
        `e` TO result.
    APPEND `FUNCTION_NAME=UniqueName~DESCRIPTION=Returns the unique name of a member.~PARAMETER_LIST=Member~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=UniqueN` &&
        `ame` TO result.
    APPEND `FUNCTION_NAME=Unorder~DESCRIPTION=Removes any enforced ordering from a specified set.~PARAMETER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTI` &&
        `ON=Unorder` TO result.
    APPEND `FUNCTION_NAME=Val~PARAMETER_LIST=Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Val` TO result.
    APPEND `FUNCTION_NAME=Val~DESCRIPTION=Returns the numbers contained in a string as a numeric value of appropriate type.~PARAMETER_LIST=String~RETURN_TYPE=5~OR` &&
        `IGIN=1~INTERFACE_NAME=~CAPTION=Val` TO result.
    APPEND `FUNCTION_NAME=ValidMeasure~DESCRIPTION=Returns a valid measure in a virtual cube by forcing inapplicable dimensions to their top level.~PARAMETER_LIST` &&
        `=Tuple~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=ValidMeasure` TO result.
    APPEND `FUNCTION_NAME=Value~DESCRIPTION=Returns the value of a measure.~PARAMETER_LIST=Member~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Value` TO result.
    APPEND `FUNCTION_NAME=Var~DESCRIPTION=Returns the variance of a numeric expression evaluated over a set (unbiased).~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~` &&
        `INTERFACE_NAME=~CAPTION=Var` TO result.
    APPEND `FUNCTION_NAME=Var~DESCRIPTION=Returns the variance of a numeric expression evaluated over a set (unbiased).~PARAMETER_LIST=Set, Numeric Expression~RET` &&
        `URN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Var` TO result.
    APPEND `FUNCTION_NAME=Variance~DESCRIPTION=Alias for Var.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Variance` TO result.
    APPEND `FUNCTION_NAME=Variance~DESCRIPTION=Alias for Var.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=Variance` TO result.
    APPEND `FUNCTION_NAME=VarianceP~DESCRIPTION=Alias for VarP.~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=VarianceP` TO result.
    APPEND `FUNCTION_NAME=VarianceP~DESCRIPTION=Alias for VarP.~PARAMETER_LIST=Set, Numeric Expression~RETURN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=VarianceP` TO result.
    APPEND `FUNCTION_NAME=VarP~DESCRIPTION=Returns the variance of a numeric expression evaluated over a set (biased).~PARAMETER_LIST=Set~RETURN_TYPE=5~ORIGIN=1~I` &&
        `NTERFACE_NAME=~CAPTION=VarP` TO result.
    APPEND `FUNCTION_NAME=VarP~DESCRIPTION=Returns the variance of a numeric expression evaluated over a set (biased).~PARAMETER_LIST=Set, Numeric Expression~RETU` &&
        `RN_TYPE=5~ORIGIN=1~INTERFACE_NAME=~CAPTION=VarP` TO result.
    APPEND `FUNCTION_NAME=VisualTotals~DESCRIPTION=Dynamically totals child members specified in a set using a pattern for the total label in the result set.~PARA` &&
        `METER_LIST=Set~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=VisualTotals` TO result.
    APPEND `FUNCTION_NAME=VisualTotals~DESCRIPTION=Dynamically totals child members specified in a set using a pattern for the total label in the result set.~PARA` &&
        `METER_LIST=Set, String~RETURN_TYPE=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=VisualTotals` TO result.
    APPEND `FUNCTION_NAME=Weekday~DESCRIPTION=Returns a Variant (Integer) containing a whole number representing the day of the week.~PARAMETER_LIST=DateTime, Int` &&
        `eger~RETURN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Weekday` TO result.
    APPEND `FUNCTION_NAME=Weekday~DESCRIPTION=Returns a Variant (Integer) containing a whole number representing the day of the week.~PARAMETER_LIST=DateTime~RETU` &&
        `RN_TYPE=2~ORIGIN=1~INTERFACE_NAME=~CAPTION=Weekday` TO result.
    APPEND `FUNCTION_NAME=WeekdayName~DESCRIPTION=Returns a string indicating the specified day of the week.~PARAMETER_LIST=Integer, Logical Expression, Integer~R` &&
        `ETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=WeekdayName` TO result.
    APPEND `FUNCTION_NAME=Wtd~DESCRIPTION=A shortcut function for the PeriodsToDate function that specifies the level to be Week.~PARAMETER_LIST=~RETURN_TYPE=12~O` &&
        `RIGIN=1~INTERFACE_NAME=~CAPTION=Wtd` TO result.
    APPEND `FUNCTION_NAME=Wtd~DESCRIPTION=A shortcut function for the PeriodsToDate function that specifies the level to be Week.~PARAMETER_LIST=Member~RETURN_TYP` &&
        `E=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Wtd` TO result.
    APPEND `FUNCTION_NAME=XOR~DESCRIPTION=Returns whether two conditions are mutually exclusive.~PARAMETER_LIST=Logical Expression, Logical Expression~RETURN_TYPE` &&
        `=11~ORIGIN=1~INTERFACE_NAME=~CAPTION=XOR` TO result.
    APPEND `FUNCTION_NAME=Year~DESCRIPTION=Returns a Variant (Integer) containing a whole number representing the year.~PARAMETER_LIST=DateTime~RETURN_TYPE=2~ORIG` &&
        `IN=1~INTERFACE_NAME=~CAPTION=Year` TO result.
    APPEND `FUNCTION_NAME=Ytd~DESCRIPTION=A shortcut function for the PeriodsToDate function that specifies the level to be Year.~PARAMETER_LIST=~RETURN_TYPE=12~O` &&
        `RIGIN=1~INTERFACE_NAME=~CAPTION=Ytd` TO result.
    APPEND `FUNCTION_NAME=Ytd~DESCRIPTION=A shortcut function for the PeriodsToDate function that specifies the level to be Year.~PARAMETER_LIST=Member~RETURN_TYP` &&
        `E=12~ORIGIN=1~INTERFACE_NAME=~CAPTION=Ytd` TO result.
    APPEND `FUNCTION_NAME={}~DESCRIPTION=Brace operator constructs a set.~PARAMETER_LIST=(none)~RETURN_TYPE=1~ORIGIN=1~INTERFACE_NAME=~CAPTION={}` TO result.
    APPEND `FUNCTION_NAME=||~DESCRIPTION=Concatenates two strings.~PARAMETER_LIST=String, String~RETURN_TYPE=8~ORIGIN=1~INTERFACE_NAME=~CAPTION=||` TO result.
  ENDMETHOD.
ENDCLASS.
