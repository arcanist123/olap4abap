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
"! The evaluation context of a query: the port of Evaluator (RolapEvaluator with RolapEvaluatorRoot). It
"! holds the current member of every hierarchy of the cube, at first its default member, and reads the cell of the
"! current context from the facts (the CellReader). Changes of the context are recorded on a command stack and undone
"! back to a savepoint (savepoint / restore); push gives a child evaluator with a copy of the context. A calculated
"! member in the context is a calculation: the cell is then the value of the formula of the calculation that expands
"! first (SolveOrderMode SCOPED, as the reference server is configured), evaluated through ZZXXMLA1_IF_MDX_CALC. Not yet: tuple
"! calculations, aggregation lists and the expression cache.
CLASS zzxxmla1_cl_mdx_evaluator DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    INTERFACES zzxxmla1_if_mdx_evaluator.
    ALIASES push FOR zzxxmla1_if_mdx_evaluator~push.
    ALIASES get_parent FOR zzxxmla1_if_mdx_evaluator~get_parent.
    ALIASES get_schema_reader FOR zzxxmla1_if_mdx_evaluator~get_schema_reader.
    ALIASES savepoint FOR zzxxmla1_if_mdx_evaluator~savepoint.
    ALIASES restore FOR zzxxmla1_if_mdx_evaluator~restore.
    ALIASES set_context FOR zzxxmla1_if_mdx_evaluator~set_context.
    ALIASES set_context_members FOR zzxxmla1_if_mdx_evaluator~set_context_members.
    ALIASES get_context FOR zzxxmla1_if_mdx_evaluator~get_context.
    ALIASES get_members FOR zzxxmla1_if_mdx_evaluator~get_members.
    ALIASES set_slicer_context FOR zzxxmla1_if_mdx_evaluator~set_slicer_context.
    ALIASES get_slicer_members FOR zzxxmla1_if_mdx_evaluator~get_slicer_members.
    ALIASES set_cell_reader FOR zzxxmla1_if_mdx_evaluator~set_cell_reader.
    ALIASES is_non_empty FOR zzxxmla1_if_mdx_evaluator~is_non_empty.
    ALIASES set_non_empty FOR zzxxmla1_if_mdx_evaluator~set_non_empty.
    ALIASES is_eval_axes FOR zzxxmla1_if_mdx_evaluator~is_eval_axes.
    ALIASES set_eval_axes FOR zzxxmla1_if_mdx_evaluator~set_eval_axes.
    ALIASES evaluate_current FOR zzxxmla1_if_mdx_evaluator~evaluate_current.
    ALIASES current_is_empty FOR zzxxmla1_if_mdx_evaluator~current_is_empty.
    ALIASES get_format_string FOR zzxxmla1_if_mdx_evaluator~get_format_string.
    TYPES ty_member TYPE zzxxmla1_if_mdx_evaluator=>ty_member.
    TYPES ty_t_member TYPE zzxxmla1_if_mdx_evaluator=>ty_t_member.
    CONSTANTS:
      BEGIN OF c_value,
        numeric TYPE string VALUE `NUMERIC`,
        integer TYPE string VALUE `INTEGER`,
        string  TYPE string VALUE `STRING`,
        logical TYPE string VALUE `LOGICAL`,
        error     TYPE string VALUE `ERROR`,
        order_key TYPE string VALUE `ORDERKEY`,
      END OF c_value.
    TYPES ty_value TYPE zzxxmla1_if_mdx_evaluator=>ty_value.

    "! A root evaluator (RolapEvaluator(root)): every hierarchy at its default member.
    "! @parameter calc | evaluates the formulas of calculated members and format expressions
    CLASS-METHODS create
      IMPORTING schema_reader TYPE REF TO zzxxmla1_if_mdx_schema_reader
                facts         TYPE REF TO zzxxmla1_cl_mdx_facts
                calc          TYPE REF TO zzxxmla1_if_mdx_calc OPTIONAL
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_evaluator.
    "! RolapCalculation.getCompiledExpression of a member made while the query runs (the placeholder of a compound
    "! slicer, a visual total): its calculation of its own, kept by the root evaluator for all the evaluators of the
    "! query (RolapEvaluatorRoot) and found as get_calculation finds the member (a visual total by its calc_name).
    METHODS set_compiled
      IMPORTING member TYPE ty_member
                calc   TYPE REF TO zzxxmla1_if_mdx_calc.
    "! The calculation of its own of a member (set_compiled); not bound for any other member.
    METHODS get_compiled
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_if_mdx_calc.

    "! String.valueOf: a value as text (a double as Double.toString).
    CLASS-METHODS to_text
      IMPORTING value         TYPE ty_value
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    CONSTANTS:
      BEGIN OF c_command,
        savepoint     TYPE i VALUE 0,
        set_context   TYPE i VALUE 1,
        set_non_empty TYPE i VALUE 2,
        set_eval_axes TYPE i VALUE 3,
        set_expanding TYPE i VALUE 4,
        set_cell_reader TYPE i VALUE 5,
      END OF c_command.
    TYPES:
      "! A command of the stack: what restore does to undo a change (Command and its arguments).
      BEGIN OF ty_command,
        command TYPE i,
        ordinal TYPE i,
        member  TYPE ty_member,
        flag    TYPE abap_bool,
      END OF ty_command,
      ty_t_command TYPE STANDARD TABLE OF ty_command WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_compiled,
        name TYPE string,
        calc TYPE REF TO zzxxmla1_if_mdx_calc,
      END OF ty_compiled,
      ty_t_compiled TYPE HASHED TABLE OF ty_compiled WITH UNIQUE KEY name.

    DATA schema_reader   TYPE REF TO zzxxmla1_if_mdx_schema_reader.
    "! the root evaluator of the query (RolapEvaluatorRoot), which keeps the compiled calculations
    DATA root            TYPE REF TO zzxxmla1_cl_mdx_evaluator.
    "! root only: the calculations of their own of members made while the query runs (set_compiled)
    DATA compiled        TYPE ty_t_compiled.
    DATA facts           TYPE REF TO zzxxmla1_cl_mdx_facts.
    DATA parent          TYPE REF TO zzxxmla1_cl_mdx_evaluator.
    "! the current member of the hierarchy with id n at position n + 1
    DATA current_members TYPE ty_t_member.
    "! the number of calculated members and of null members among the current members (set_context_unsafe): a context
    "! without them needs no search for them in every cell
    DATA calculated_count TYPE i.
    DATA null_count       TYPE i.
    "! the hierarchies (but Measures) whose current member is below the All level, in hierarchy order: the filters of
    "! the cell reader
    DATA non_all          TYPE SORTED TABLE OF i WITH UNIQUE KEY table_line.
    "! the stored measures of the cube, read once
    DATA measures         TYPE zzxxmla1_cl_model=>ty_t_measure.
    DATA slicer_members  TYPE ty_t_member.
    DATA non_empty       TYPE abap_bool.
    DATA eval_axes       TYPE abap_bool.
    DATA commands        TYPE ty_t_command.
    DATA calc            TYPE REF TO zzxxmla1_if_mdx_calc.
    "! the number of calculations being expanded: a last guard against endless recursion, which check_recursion finds
    "! first
    DATA expanding       TYPE i.
    CONSTANTS c_max_expanding TYPE i VALUE 1000.
    "! the calculated member being expanded (expandingMember)
    DATA expanding_member TYPE ty_member.
    "! the size of the command stack as the reference counts it (commandCount: each command and its arguments), and of the
    "! stacks of the ancestors (ancestorCommandCount)
    DATA command_count          TYPE i.
    DATA ancestor_command_count TYPE i.
    "! RolapEvaluatorRoot.recursionCheckCommandCount, shared by the evaluators of the query
    DATA recursion_check        TYPE REF TO i.
    "! The key of a member's calculation: a visual total's calc_name, else its unique name (as get_calculation).
    CLASS-METHODS calculation_key
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE string.
    "! Command.width: the command and its arguments.
    CLASS-METHODS width
      IMPORTING command       TYPE i
      RETURNING VALUE(result) TYPE i.
    "! Records a command (commands[commandCount++] = ...).
    METHODS add_command
      IMPORTING command TYPE ty_command.
    "! setExpanding: makes the member the one being expanded; once the stacks have grown by 16 commands per hierarchy
    "! since the last check, checks for an infinite loop.
    METHODS set_expanding
      IMPORTING member TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! checkRecursion: an ancestor state (in this evaluator before the command at the index, then in its parents) with
    "! the same context expanding the same member is an infinite loop.
    METHODS check_recursion
      IMPORTING index TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! getContextString: the context at each savepoint after which it changed, from the innermost, without the
    "! hierarchies' default members.
    METHODS context_string
      RETURNING VALUE(result) TYPE string.
    "! Whether two contexts have the same members (Arrays.equals).
    CLASS-METHODS same_members
      IMPORTING members1      TYPE ty_t_member
                members2      TYPE ty_t_member
      RETURNING VALUE(result) TYPE abap_bool.

    "! getScopedMaxSolveOrder: the calculated member of the context to expand first; initial if there is none.
    METHODS max_solve_calculation
      RETURNING VALUE(result) TYPE ty_member.
    "! expandsBefore: the higher solve order, on a tie the lower hierarchy ordinal.
    CLASS-METHODS expands_before
      IMPORTING calculation1  TYPE ty_member
                calculation2  TYPE ty_member
      RETURNING VALUE(result) TYPE abap_bool.
    "! setContext( member, false ): changes the context without recording it.
    METHODS set_context_unsafe
      IMPORTING member TYPE ty_member.
    "! setContext( member ): set_context without the previous member as result.
    METHODS change_context
      IMPORTING member TYPE ty_member.
    "! Whether a change of the hierarchy is already recorded since the last savepoint.
    METHODS exists
      IMPORTING ordinal       TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_evaluator IMPLEMENTATION.

  METHOD create.
    result = NEW #( ).
    result->root = result.
    result->schema_reader = schema_reader.
    result->facts = facts.
    result->calc = calc.
    LOOP AT schema_reader->get_hierarchies( ) INTO DATA(hierarchy).
      INSERT schema_reader->get_default_member( hierarchy-id ) INTO result->current_members INDEX hierarchy-id + 1.
    ENDLOOP.
    LOOP AT result->current_members ASSIGNING FIELD-SYMBOL(<member>).
      IF <member>-calculated = abap_true.
        result->calculated_count = result->calculated_count + 1.
      ENDIF.
      IF <member>-is_null = abap_true.
        result->null_count = result->null_count + 1.
      ENDIF.
      IF <member>-hier_id > 0 AND <member>-key_level > 0.
        INSERT <member>-hier_id INTO TABLE result->non_all.
      ENDIF.
    ENDLOOP.
    result->measures = schema_reader->get_measures( ).
    " the sentinel
    result->commands = VALUE #( ( command = c_command-savepoint ) ).
    result->command_count = 1.
    result->recursion_check = NEW #( lines( result->current_members ) * 16 ).
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~push.
    DATA(child) = NEW zzxxmla1_cl_mdx_evaluator( ).
    child->root = root.
    child->schema_reader = schema_reader.
    child->facts = facts.
    child->calc = calc.
    child->expanding = expanding.
    child->parent = me.
    child->current_members = current_members.
    child->calculated_count = calculated_count.
    child->null_count = null_count.
    child->non_all = non_all.
    child->measures = measures.
    child->slicer_members = slicer_members.
    child->non_empty = non_empty.
    child->eval_axes = eval_axes.
    child->expanding_member = expanding_member.
    child->commands = VALUE #( ( command = c_command-savepoint ) ).
    child->command_count = 1.
    child->ancestor_command_count = ancestor_command_count + command_count.
    child->recursion_check = recursion_check.
    result = child.
  ENDMETHOD.

  METHOD set_compiled.
    INSERT VALUE #( name = calculation_key( member ) calc = calc ) INTO TABLE root->compiled.
  ENDMETHOD.

  METHOD get_compiled.
    READ TABLE root->compiled INTO DATA(entry) WITH TABLE KEY name = calculation_key( member ).
    IF sy-subrc = 0.
      result = entry-calc.
    ENDIF.
  ENDMETHOD.

  METHOD calculation_key.
    result = COND #( WHEN member-calc_name IS INITIAL THEN member-unique_name ELSE member-calc_name ).
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~get_parent.
    result = parent.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~get_schema_reader.
    result = schema_reader.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~savepoint.
    result = lines( commands ).
    IF commands[ result ]-command = c_command-savepoint.
      " already at a savepoint
      RETURN.
    ENDIF.
    APPEND INITIAL LINE TO commands ASSIGNING FIELD-SYMBOL(<command>).
    <command>-command = c_command-savepoint.
    command_count = command_count + 1.
  ENDMETHOD.

  METHOD width.
    result = SWITCH #( command WHEN c_command-savepoint THEN 1
                               WHEN c_command-set_context OR c_command-set_expanding THEN 3
                               ELSE 2 ).
  ENDMETHOD.

  METHOD add_command.
    APPEND command TO commands.
    command_count = command_count + width( command-command ).
  ENDMETHOD.

  METHOD set_expanding.
    add_command( VALUE #( command = c_command-set_expanding member = expanding_member ) ).
    expanding_member = member.
    DATA(total) = command_count + ancestor_command_count.
    IF total > recursion_check->*.
      check_recursion( lines( commands ) - 1 ).
      recursion_check->* = total + lines( current_members ) * 16.
    ENDIF.
  ENDMETHOD.

  METHOD check_recursion.
    DATA(members) = current_members.
    DATA(evaluator) = me.
    DATA(position) = index.
    DO.
      IF position < 1.
        evaluator = evaluator->parent.
        IF evaluator IS NOT BOUND.
          RETURN.
        ENDIF.
        position = lines( evaluator->commands ).
        CONTINUE.
      ENDIF.
      DATA(command) = evaluator->commands[ position ].
      CASE command-command.
        WHEN c_command-set_context.
          members[ command-ordinal + 1 ] = command-member.
        WHEN c_command-set_expanding.
          IF same_members( members1 = members members2 = evaluator->current_members ) = abap_true
              AND command-member-unique_name = evaluator->expanding_member-unique_name
              AND command-member-calc_name = evaluator->expanding_member-calc_name.
            zzxxmla1_cx_mdx_evaluation=>raise_error(
              |Infinite loop while evaluating calculated member '{ evaluator->expanding_member-unique_name }'; | &&
              |context stack is { evaluator->context_string( ) }| ).
          ENDIF.
      ENDCASE.
      position = position - 1.
    ENDDO.
  ENDMETHOD.

  METHOD context_string.
    DATA(members) = current_members.
    DATA(frames) = 0.
    DATA(changed) = abap_false.
    result = `{`.
    DATA(evaluator) = me.
    WHILE evaluator IS BOUND.
      IF evaluator->expanding_member IS NOT INITIAL.
        DATA(position) = lines( evaluator->commands ).
        WHILE position > 1.
          DATA(command) = evaluator->commands[ position ].
          CASE command-command.
            WHEN c_command-savepoint.
              IF changed = abap_true.
                IF frames > 0.
                  result = result && `, `.
                ENDIF.
                frames = frames + 1.
                DATA(names) = VALUE string_table( ).
                LOOP AT members INTO DATA(member).
                  IF member-unique_name = schema_reader->get_default_member( member-hier_id )-unique_name
                      AND member-calc_name IS INITIAL.
                    CONTINUE.
                  ENDIF.
                  APPEND member-unique_name TO names.
                ENDLOOP.
                result = |{ result }({ concat_lines_of( table = names sep = `, ` ) })|.
              ENDIF.
              changed = abap_false.
            WHEN c_command-set_context.
              changed = abap_true.
              members[ command-ordinal + 1 ] = command-member.
          ENDCASE.
          position = position - 1.
        ENDWHILE.
      ENDIF.
      evaluator = evaluator->parent.
    ENDWHILE.
    result = result && `}`.
  ENDMETHOD.

  METHOD same_members.
    IF lines( members1 ) <> lines( members2 ).
      RETURN.
    ENDIF.
    LOOP AT members1 INTO DATA(member1).
      DATA(member2) = REF #( members2[ sy-tabix ] ).
      IF member1-unique_name <> member2->unique_name OR member1-calc_name <> member2->calc_name.
        RETURN.
      ENDIF.
    ENDLOOP.
    result = abap_true.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~restore.
    " undone in place, from the last command (this runs for every cell)
    DATA(last) = lines( commands ).
    WHILE last > savepoint.
      ASSIGN commands[ last ] TO FIELD-SYMBOL(<command>).
      CASE <command>-command.
        WHEN c_command-savepoint.
          command_count = command_count - 1.
        WHEN c_command-set_context.
          command_count = command_count - 3.
          set_context_unsafe( <command>-member ).
        WHEN c_command-set_non_empty.
          command_count = command_count - 2.
          non_empty = <command>-flag.
        WHEN c_command-set_eval_axes.
          command_count = command_count - 2.
          eval_axes = <command>-flag.
        WHEN c_command-set_expanding.
          command_count = command_count - 3.
          expanding_member = <command>-member.
        WHEN OTHERS.
          command_count = command_count - width( <command>-command ).
      ENDCASE.
      DELETE commands INDEX last.
      last = last - 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~set_context.
    result = current_members[ member-hier_id + 1 ].
    change_context( member ).
  ENDMETHOD.

  METHOD change_context.
    DATA(ordinal) = member-hier_id.
    ASSIGN current_members[ ordinal + 1 ] TO FIELD-SYMBOL(<current>).
    " the same member (a visual total member has the unique name of the member it stands for)
    IF member-unique_name = <current>-unique_name AND member-calc_name = <current>-calc_name.
      RETURN.
    ENDIF.
    IF exists( ordinal ) = abap_false.
      " add_command, in place: Command.SET_CONTEXT is 3 wide
      APPEND INITIAL LINE TO commands ASSIGNING FIELD-SYMBOL(<command>).
      <command>-command = c_command-set_context.
      <command>-ordinal = ordinal.
      <command>-member = <current>.
      command_count = command_count + 3.
    ENDIF.
    set_context_unsafe( member ).
  ENDMETHOD.

  METHOD set_context_unsafe.
    ASSIGN current_members[ member-hier_id + 1 ] TO FIELD-SYMBOL(<current>).
    IF <current>-calculated <> member-calculated.
      calculated_count = calculated_count + COND i( WHEN member-calculated = abap_true THEN 1 ELSE -1 ).
    ENDIF.
    IF <current>-is_null <> member-is_null.
      null_count = null_count + COND i( WHEN member-is_null = abap_true THEN 1 ELSE -1 ).
    ENDIF.
    IF member-hier_id > 0 AND xsdbool( <current>-key_level > 0 ) <> xsdbool( member-key_level > 0 ).
      IF member-key_level > 0.
        INSERT member-hier_id INTO TABLE non_all.
      ELSE.
        DELETE TABLE non_all WITH TABLE KEY table_line = member-hier_id.
      ENDIF.
    ENDIF.
    <current> = member.
  ENDMETHOD.

  METHOD exists.
    DATA(index) = lines( commands ).
    WHILE index > 0.
      DATA(command) = REF #( commands[ index ] ).
      CASE command->command.
        WHEN c_command-savepoint.
          RETURN.
        WHEN c_command-set_context.
          IF command->ordinal = ordinal.
            result = abap_true.
            RETURN.
          ENDIF.
      ENDCASE.
      index = index - 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~set_context_members.
    LOOP AT members ASSIGNING FIELD-SYMBOL(<member>).
      change_context( <member> ).
    ENDLOOP.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~get_context.
    result = current_members[ hierarchy + 1 ].
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~get_members.
    result = current_members.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~set_slicer_context.
    set_context_members( members ).
    APPEND LINES OF members TO slicer_members.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~get_slicer_members.
    result = slicer_members.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~set_cell_reader.
    add_command( VALUE #( command = c_command-set_cell_reader ) ).
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~is_non_empty.
    result = non_empty.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~set_non_empty.
    IF non_empty <> me->non_empty.
      add_command( VALUE #( command = c_command-set_non_empty flag = me->non_empty ) ).
      me->non_empty = non_empty.
    ENDIF.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~is_eval_axes.
    result = eval_axes.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~set_eval_axes.
    IF eval_axes <> me->eval_axes.
      add_command( VALUE #( command = c_command-set_eval_axes flag = me->eval_axes ) ).
      me->eval_axes = eval_axes.
    ENDIF.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~evaluate_current.
    DATA(calculation) = max_solve_calculation( ).
    IF calculation-unique_name IS INITIAL.
      " a null member in the context: no cell request, the value is null (RolapAggregationManager.makeRequest)
      IF null_count > 0.
        result-empty = abap_true.
        RETURN.
      ENDIF.
      " the cell reader: the measure of the context aggregated over the facts of its other non-All members
      DATA(filters) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_filter( ).
      LOOP AT non_all INTO DATA(hierarchy).
        ASSIGN current_members[ hierarchy + 1 ] TO FIELD-SYMBOL(<member>).
        APPEND VALUE #( hierarchy = hierarchy level = <member>-key_level path = <member>-path ) TO filters.
      ENDLOOP.
      DATA(cell) = facts->value( filters = filters measure = current_members[ 1 ]-measure_index ).
      result = VALUE #( empty = cell-empty kind = c_value-numeric number = cell-amount ).
      RETURN.
    ENDIF.

    IF expanding >= c_max_expanding.
      zzxxmla1_cx_mdx_evaluation=>raise_error(
        |Infinite loop while evaluating calculated member '{ calculation-unique_name }'| ).
    ENDIF.
    DATA(definition) = schema_reader->get_calculation( calculation ).
    " getCompiledExpression: the calculation of its own, else the formula
    DATA(own) = get_compiled( calculation ).
    DATA(compiled) = COND #( WHEN own IS BOUND THEN own ELSE calc ).
    DATA(saved) = savepoint( ).
    expanding = expanding + 1.
    TRY.
        " setContextIn: the calculation's hierarchy at its default member, the calculation being expanded, then the
        " formula
        set_context( schema_reader->get_default_member( calculation-hier_id ) ).
        set_expanding( calculation ).
        result = compiled->evaluate( evaluator = me node = definition-expression ).
      CLEANUP.
        expanding = expanding - 1.
        restore( saved ).
    ENDTRY.
    expanding = expanding - 1.
    restore( saved ).
  ENDMETHOD.

  METHOD max_solve_calculation.
    " SCOPED (the finite state machine of getScopedMaxSolveOrder): a calculation with Aggregate gives way to any
    " without; one of the cube (the placeholder of a compound slicer) gives way to one of the query; within a scope the
    " one that expands first wins. The calculations in the order of their hierarchies.
    CONSTANTS:
      BEGIN OF c_state,
        start TYPE i VALUE 0,
        aggregate TYPE i VALUE 1,
        cube TYPE i VALUE 2,
        query TYPE i VALUE 3,
      END OF c_state.
    IF calculated_count = 0.
      RETURN.
    ENDIF.
    DATA(state) = c_state-start.
    LOOP AT current_members INTO DATA(member) WHERE calculated = abap_true.
      DATA(definition) = schema_reader->get_calculation( member ).
      DATA(aggregate) = definition-contains_aggregate.
      DATA(in_query) = xsdbool( definition-cube_scope = abap_false ).
      CASE state.
        WHEN c_state-start.
          result = member.
          state = COND #( WHEN aggregate = abap_true THEN c_state-aggregate
                          WHEN in_query = abap_true THEN c_state-query ELSE c_state-cube ).
        WHEN c_state-aggregate.
          IF aggregate = abap_true.
            IF expands_before( calculation1 = member calculation2 = result ) = abap_true.
              result = member.
            ENDIF.
          ELSE.
            result = member.
            state = COND #( WHEN in_query = abap_true THEN c_state-query ELSE c_state-cube ).
          ENDIF.
        WHEN c_state-cube.
          IF aggregate = abap_true.
            CONTINUE.
          ENDIF.
          IF in_query = abap_true.
            result = member.
            state = c_state-query.
          ELSEIF expands_before( calculation1 = member calculation2 = result ) = abap_true.
            result = member.
          ENDIF.
        WHEN c_state-query.
          IF aggregate = abap_false AND in_query = abap_true
              AND expands_before( calculation1 = member calculation2 = result ) = abap_true.
            result = member.
          ENDIF.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD expands_before.
    result = xsdbool( calculation1-solve_order > calculation2-solve_order
                      OR ( calculation1-solve_order = calculation2-solve_order
                           AND calculation1-hier_id < calculation2-hier_id ) ).
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~get_format_string.
    " getProperty(FORMAT_EXP_PARSED): stored members other than measures have no format; a stored measure has the
    " solve order -1 and its format string (empty if none)
    DATA format_expression TYPE REF TO zzxxmla1_cl_mdx_node.
    DATA(max_solve) = cl_abap_math=>min_int4.
    DATA(found) = abap_false.
    " only calculated members and the measure have a format
    LOOP AT current_members ASSIGNING FIELD-SYMBOL(<member>)
         WHERE calculated = abap_true OR hier_id = zzxxmla1_if_mdx_schema_reader=>c_measures.
      IF <member>-calculated = abap_true.
        IF <member>-solve_order > max_solve.
          DATA(expression) = schema_reader->get_calculation( <member> )-format_expression.
          IF expression IS BOUND.
            format_expression = expression.
            max_solve = <member>-solve_order.
            found = abap_true.
          ENDIF.
        ENDIF.
      ELSEIF -1 > max_solve.
        CLEAR format_expression.
        result = measures[ <member>-measure_index ]-format.
        max_solve = -1.
        found = abap_true.
      ENDIF.
      IF calculated_count = 0.
        " the measure was the only one
        EXIT.
      ENDIF.
    ENDLOOP.
    IF found = abap_false.
      result = `Standard`.
    ELSEIF format_expression IS BOUND.
      DATA(value) = calc->evaluate( evaluator = me node = format_expression ).
      result = COND #( WHEN value-empty = abap_true THEN `Standard` ELSE to_text( value ) ).
    ENDIF.
  ENDMETHOD.

  METHOD to_text.
    IF value-empty = abap_true.
      result = `null`.
      RETURN.
    ENDIF.
    CASE value-kind.
      WHEN c_value-numeric.
        result = SWITCH #( value-special WHEN `INF` THEN `Infinity` WHEN `-INF` THEN `-Infinity` WHEN `NAN` THEN `NaN`
                           ELSE zzxxmla1_cl_mdx_format=>java_double( value-number ) ).
      WHEN c_value-integer.
        result = |{ CONV int8( value-number ) }|.
      WHEN c_value-logical.
        result = COND #( WHEN value-boolean = abap_true THEN `true` ELSE `false` ).
      WHEN OTHERS.
        result = value-text.
    ENDCASE.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_evaluator~current_is_empty.
    IF evaluate_current( )-empty = abap_true.
      result = abap_true.
      RETURN.
    ENDIF.
    " a value such as zero is empty if no fact row is in the cell
    DATA(fact_count) = line_index( measures[ aggregator = `count` ] ).
    IF fact_count = 0.
      RETURN.
    ENDIF.
    DATA(saved) = savepoint( ).
    set_context( schema_reader->measure_member( fact_count ) ).
    DATA(value) = evaluate_current( ).
    restore( saved ).
    result = xsdbool( value-empty = abap_true OR value-number = 0 ).
  ENDMETHOD.

ENDCLASS.
