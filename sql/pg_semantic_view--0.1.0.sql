CREATE SCHEMA IF NOT EXISTS semantic;

CREATE TABLE semantic.views (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL UNIQUE,
    description text,
    default_base_logical_table text,
    source_format text,
    source_version text,
    ai_context jsonb NOT NULL DEFAULT '{}'::jsonb,
    options jsonb NOT NULL DEFAULT '{}'::jsonb,
    extensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE semantic.logical_tables (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    view_id bigint NOT NULL REFERENCES semantic.views(id) ON DELETE CASCADE,
    name text NOT NULL,
    table_alias text NOT NULL,
    physical_table regclass NOT NULL,
    dataset_kind text NOT NULL DEFAULT 'fact',
    primary_key_columns jsonb NOT NULL DEFAULT '[]'::jsonb,
    unique_key_sets jsonb NOT NULL DEFAULT '[]'::jsonb,
    source_mapping jsonb NOT NULL DEFAULT '{}'::jsonb,
    description text,
    extensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (view_id, name),
    UNIQUE (view_id, table_alias)
);

CREATE TABLE semantic.relationships (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    view_id bigint NOT NULL REFERENCES semantic.views(id) ON DELETE CASCADE,
    name text NOT NULL,
    from_table_id bigint NOT NULL REFERENCES semantic.logical_tables(id) ON DELETE CASCADE,
    to_table_id bigint NOT NULL REFERENCES semantic.logical_tables(id) ON DELETE CASCADE,
    join_sql text NOT NULL,
    cardinality text NOT NULL DEFAULT 'many_to_one',
    description text,
    extensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (view_id, name),
    CHECK (from_table_id <> to_table_id)
);

CREATE TABLE semantic.dimensions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    view_id bigint NOT NULL REFERENCES semantic.views(id) ON DELETE CASCADE,
    logical_table_id bigint NOT NULL REFERENCES semantic.logical_tables(id) ON DELETE CASCADE,
    name text NOT NULL,
    expression_sql text NOT NULL,
    description text,
    synonyms jsonb NOT NULL DEFAULT '[]'::jsonb,
    data_type text,
    time_granularity text,
    extensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (view_id, name)
);

CREATE TABLE semantic.facts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    view_id bigint NOT NULL REFERENCES semantic.views(id) ON DELETE CASCADE,
    logical_table_id bigint NOT NULL REFERENCES semantic.logical_tables(id) ON DELETE CASCADE,
    name text NOT NULL,
    expression_sql text NOT NULL,
    description text,
    synonyms jsonb NOT NULL DEFAULT '[]'::jsonb,
    data_type text,
    visibility text NOT NULL DEFAULT 'public',
    extensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (view_id, name),
    CHECK (visibility IN ('public', 'private'))
);

CREATE TABLE semantic.metrics (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    view_id bigint NOT NULL REFERENCES semantic.views(id) ON DELETE CASCADE,
    logical_table_id bigint REFERENCES semantic.logical_tables(id) ON DELETE CASCADE,
    name text NOT NULL,
    expression_sql text NOT NULL,
    expression_canonical jsonb,
    expression_language text NOT NULL DEFAULT 'postgresql_sql',
    description text,
    synonyms jsonb NOT NULL DEFAULT '[]'::jsonb,
    visibility text NOT NULL DEFAULT 'public',
    aggregation_kind text NOT NULL DEFAULT 'custom',
    extensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (view_id, name),
    CHECK (visibility IN ('public', 'private'))
);

CREATE TABLE semantic.metric_dependencies (
    metric_id bigint NOT NULL REFERENCES semantic.metrics(id) ON DELETE CASCADE,
    depends_on_metric_id bigint NOT NULL REFERENCES semantic.metrics(id) ON DELETE CASCADE,
    PRIMARY KEY (metric_id, depends_on_metric_id),
    CHECK (metric_id <> depends_on_metric_id)
);

CREATE TABLE semantic.examples (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    view_id bigint NOT NULL REFERENCES semantic.views(id) ON DELETE CASCADE,
    name text NOT NULL,
    question text,
    example_sql text,
    context jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (view_id, name)
);

CREATE INDEX semantic_logical_tables_view_id_idx
    ON semantic.logical_tables(view_id);

CREATE INDEX semantic_relationships_view_id_idx
    ON semantic.relationships(view_id);

CREATE INDEX semantic_dimensions_view_id_idx
    ON semantic.dimensions(view_id);

CREATE INDEX semantic_facts_view_id_idx
    ON semantic.facts(view_id);

CREATE INDEX semantic_metrics_view_id_idx
    ON semantic.metrics(view_id);

CREATE OR REPLACE FUNCTION semantic.assert_jsonb_type(
    p_value jsonb,
    p_expected_type text,
    p_label text
) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_value IS NULL THEN
        RETURN;
    END IF;

    IF jsonb_typeof(p_value) IS DISTINCT FROM p_expected_type THEN
        RAISE EXCEPTION '% must be a JSON %.', p_label, p_expected_type;
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.jsonb_to_text_array(
    p_value jsonb
) RETURNS text[]
LANGUAGE plpgsql
AS $function$
DECLARE
    v_result text[];
BEGIN
    IF p_value IS NULL THEN
        RETURN ARRAY[]::text[];
    END IF;

    PERFORM semantic.assert_jsonb_type(p_value, 'array', 'JSON value');

    SELECT COALESCE(array_agg(value), ARRAY[]::text[])
    INTO v_result
    FROM jsonb_array_elements_text(p_value) AS t(value);

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.require_view_id(
    p_view_name text
) RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_view_id bigint;
BEGIN
    SELECT id
    INTO v_view_id
    FROM semantic.views
    WHERE name = p_view_name;

    IF v_view_id IS NULL THEN
        RAISE EXCEPTION 'Semantic view "%" does not exist.', p_view_name;
    END IF;

    RETURN v_view_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.require_logical_table_id(
    p_view_id bigint,
    p_table_name text
) RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_table_id bigint;
BEGIN
    SELECT id
    INTO v_table_id
    FROM semantic.logical_tables
    WHERE view_id = p_view_id
      AND name = p_table_name;

    IF v_table_id IS NULL THEN
        RAISE EXCEPTION 'Logical table "%" does not exist in semantic view id %.', p_table_name, p_view_id;
    END IF;

    RETURN v_table_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.require_relation(
    p_relation text
) RETURNS regclass
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_relation regclass;
BEGIN
    SELECT to_regclass(p_relation)
    INTO v_relation;

    IF v_relation IS NULL THEN
        RAISE EXCEPTION 'Physical table "%" does not exist.', p_relation;
    END IF;

    RETURN v_relation;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.register_metric_dependencies(
    p_view_name text,
    p_metric_name text,
    p_depends_on_metrics text[]
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_metric_id bigint;
    v_dependency_name text;
    v_dependency_id bigint;
BEGIN
    IF COALESCE(cardinality(p_depends_on_metrics), 0) = 0 THEN
        RETURN;
    END IF;

    v_view_id := semantic.require_view_id(p_view_name);

    SELECT id
    INTO v_metric_id
    FROM semantic.metrics
    WHERE view_id = v_view_id
      AND name = p_metric_name;

    IF v_metric_id IS NULL THEN
        RAISE EXCEPTION 'Metric "%" does not exist in semantic view "%".', p_metric_name, p_view_name;
    END IF;

    FOREACH v_dependency_name IN ARRAY p_depends_on_metrics LOOP
        SELECT id
        INTO v_dependency_id
        FROM semantic.metrics
        WHERE view_id = v_view_id
          AND name = v_dependency_name;

        IF v_dependency_id IS NULL THEN
            RAISE EXCEPTION 'Metric dependency "%" does not exist in semantic view "%".', v_dependency_name, p_view_name;
        END IF;

        INSERT INTO semantic.metric_dependencies(metric_id, depends_on_metric_id)
        VALUES (v_metric_id, v_dependency_id)
        ON CONFLICT DO NOTHING;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.drop_view(
    p_view_name text
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
BEGIN
    v_view_id := semantic.require_view_id(p_view_name);

    DELETE FROM semantic.views
    WHERE id = v_view_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.add_logical_table(
    p_view_name text,
    p_logical_table_name text,
    p_physical_table text,
    p_primary_key text[] DEFAULT ARRAY[]::text[],
    p_unique_keys jsonb DEFAULT '[]'::jsonb,
    p_table_alias text DEFAULT NULL,
    p_dataset_kind text DEFAULT 'fact',
    p_source_mapping jsonb DEFAULT '{}'::jsonb,
    p_description text DEFAULT NULL,
    p_extensions jsonb DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_table_id bigint;
    v_relation regclass;
BEGIN
    PERFORM semantic.assert_jsonb_type(p_unique_keys, 'array', 'unique_keys');
    PERFORM semantic.assert_jsonb_type(p_source_mapping, 'object', 'source_mapping');
    PERFORM semantic.assert_jsonb_type(p_extensions, 'object', 'extensions');

    IF coalesce(trim(p_logical_table_name), '') = '' THEN
        RAISE EXCEPTION 'Logical table name is required.';
    END IF;

    v_view_id := semantic.require_view_id(p_view_name);
    v_relation := semantic.require_relation(p_physical_table);

    INSERT INTO semantic.logical_tables(
        view_id,
        name,
        table_alias,
        physical_table,
        dataset_kind,
        primary_key_columns,
        unique_key_sets,
        source_mapping,
        description,
        extensions
    )
    VALUES (
        v_view_id,
        p_logical_table_name,
        COALESCE(NULLIF(trim(p_table_alias), ''), p_logical_table_name),
        v_relation,
        COALESCE(NULLIF(trim(lower(p_dataset_kind)), ''), 'fact'),
        to_jsonb(COALESCE(p_primary_key, ARRAY[]::text[])),
        COALESCE(p_unique_keys, '[]'::jsonb),
        COALESCE(p_source_mapping, '{}'::jsonb),
        p_description,
        COALESCE(p_extensions, '{}'::jsonb)
    )
    RETURNING id
    INTO v_table_id;

    RETURN v_table_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.add_relationship(
    p_view_name text,
    p_relationship_name text,
    p_from_table text,
    p_to_table text,
    p_join_sql text,
    p_cardinality text DEFAULT 'many_to_one',
    p_description text DEFAULT NULL,
    p_extensions jsonb DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_from_table_id bigint;
    v_to_table_id bigint;
    v_relationship_id bigint;
BEGIN
    PERFORM semantic.assert_jsonb_type(p_extensions, 'object', 'extensions');

    IF coalesce(trim(p_relationship_name), '') = '' THEN
        RAISE EXCEPTION 'Relationship name is required.';
    END IF;

    IF coalesce(trim(p_join_sql), '') = '' THEN
        RAISE EXCEPTION 'Relationship join_sql is required.';
    END IF;

    v_view_id := semantic.require_view_id(p_view_name);
    v_from_table_id := semantic.require_logical_table_id(v_view_id, p_from_table);
    v_to_table_id := semantic.require_logical_table_id(v_view_id, p_to_table);

    INSERT INTO semantic.relationships(
        view_id,
        name,
        from_table_id,
        to_table_id,
        join_sql,
        cardinality,
        description,
        extensions
    )
    VALUES (
        v_view_id,
        p_relationship_name,
        v_from_table_id,
        v_to_table_id,
        p_join_sql,
        COALESCE(NULLIF(trim(lower(p_cardinality)), ''), 'many_to_one'),
        p_description,
        COALESCE(p_extensions, '{}'::jsonb)
    )
    RETURNING id
    INTO v_relationship_id;

    RETURN v_relationship_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.add_dimension(
    p_view_name text,
    p_logical_table_name text,
    p_dimension_name text,
    p_sql_expression text,
    p_description text DEFAULT NULL,
    p_synonyms text[] DEFAULT ARRAY[]::text[],
    p_data_type text DEFAULT NULL,
    p_time_granularity text DEFAULT NULL,
    p_extensions jsonb DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_logical_table_id bigint;
    v_dimension_id bigint;
BEGIN
    PERFORM semantic.assert_jsonb_type(p_extensions, 'object', 'extensions');

    IF coalesce(trim(p_dimension_name), '') = '' THEN
        RAISE EXCEPTION 'Dimension name is required.';
    END IF;

    IF coalesce(trim(p_sql_expression), '') = '' THEN
        RAISE EXCEPTION 'Dimension SQL expression is required.';
    END IF;

    v_view_id := semantic.require_view_id(p_view_name);
    v_logical_table_id := semantic.require_logical_table_id(v_view_id, p_logical_table_name);

    INSERT INTO semantic.dimensions(
        view_id,
        logical_table_id,
        name,
        expression_sql,
        description,
        synonyms,
        data_type,
        time_granularity,
        extensions
    )
    VALUES (
        v_view_id,
        v_logical_table_id,
        p_dimension_name,
        p_sql_expression,
        p_description,
        to_jsonb(COALESCE(p_synonyms, ARRAY[]::text[])),
        p_data_type,
        p_time_granularity,
        COALESCE(p_extensions, '{}'::jsonb)
    )
    RETURNING id
    INTO v_dimension_id;

    RETURN v_dimension_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.add_fact(
    p_view_name text,
    p_logical_table_name text,
    p_fact_name text,
    p_sql_expression text,
    p_visibility text DEFAULT 'public',
    p_description text DEFAULT NULL,
    p_synonyms text[] DEFAULT ARRAY[]::text[],
    p_data_type text DEFAULT NULL,
    p_extensions jsonb DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_logical_table_id bigint;
    v_fact_id bigint;
    v_visibility text;
BEGIN
    PERFORM semantic.assert_jsonb_type(p_extensions, 'object', 'extensions');

    IF coalesce(trim(p_fact_name), '') = '' THEN
        RAISE EXCEPTION 'Fact name is required.';
    END IF;

    IF coalesce(trim(p_sql_expression), '') = '' THEN
        RAISE EXCEPTION 'Fact SQL expression is required.';
    END IF;

    v_visibility := COALESCE(NULLIF(trim(lower(p_visibility)), ''), 'public');

    IF v_visibility NOT IN ('public', 'private') THEN
        RAISE EXCEPTION 'Fact visibility must be public or private.';
    END IF;

    v_view_id := semantic.require_view_id(p_view_name);
    v_logical_table_id := semantic.require_logical_table_id(v_view_id, p_logical_table_name);

    INSERT INTO semantic.facts(
        view_id,
        logical_table_id,
        name,
        expression_sql,
        description,
        synonyms,
        data_type,
        visibility,
        extensions
    )
    VALUES (
        v_view_id,
        v_logical_table_id,
        p_fact_name,
        p_sql_expression,
        p_description,
        to_jsonb(COALESCE(p_synonyms, ARRAY[]::text[])),
        p_data_type,
        v_visibility,
        COALESCE(p_extensions, '{}'::jsonb)
    )
    RETURNING id
    INTO v_fact_id;

    RETURN v_fact_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.add_metric(
    p_view_name text,
    p_logical_table_name text DEFAULT NULL,
    p_metric_name text DEFAULT NULL,
    p_sql_expression text DEFAULT NULL,
    p_visibility text DEFAULT 'public',
    p_description text DEFAULT NULL,
    p_synonyms text[] DEFAULT ARRAY[]::text[],
    p_aggregation_kind text DEFAULT 'custom',
    p_expression_canonical jsonb DEFAULT NULL,
    p_expression_language text DEFAULT 'postgresql_sql',
    p_extensions jsonb DEFAULT '{}'::jsonb,
    p_depends_on_metrics text[] DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_logical_table_id bigint;
    v_metric_id bigint;
    v_visibility text;
BEGIN
    PERFORM semantic.assert_jsonb_type(p_extensions, 'object', 'extensions');

    IF p_expression_canonical IS NOT NULL THEN
        PERFORM semantic.assert_jsonb_type(p_expression_canonical, 'object', 'expression_canonical');
    END IF;

    IF coalesce(trim(p_metric_name), '') = '' THEN
        RAISE EXCEPTION 'Metric name is required.';
    END IF;

    IF coalesce(trim(p_sql_expression), '') = '' THEN
        RAISE EXCEPTION 'Metric SQL expression is required.';
    END IF;

    v_visibility := COALESCE(NULLIF(trim(lower(p_visibility)), ''), 'public');

    IF v_visibility NOT IN ('public', 'private') THEN
        RAISE EXCEPTION 'Metric visibility must be public or private.';
    END IF;

    v_view_id := semantic.require_view_id(p_view_name);

    IF p_logical_table_name IS NOT NULL AND trim(p_logical_table_name) <> '' THEN
        v_logical_table_id := semantic.require_logical_table_id(v_view_id, p_logical_table_name);
    ELSE
        v_logical_table_id := NULL;
    END IF;

    INSERT INTO semantic.metrics(
        view_id,
        logical_table_id,
        name,
        expression_sql,
        expression_canonical,
        expression_language,
        description,
        synonyms,
        visibility,
        aggregation_kind,
        extensions
    )
    VALUES (
        v_view_id,
        v_logical_table_id,
        p_metric_name,
        p_sql_expression,
        p_expression_canonical,
        COALESCE(NULLIF(trim(p_expression_language), ''), 'postgresql_sql'),
        p_description,
        to_jsonb(COALESCE(p_synonyms, ARRAY[]::text[])),
        v_visibility,
        COALESCE(NULLIF(trim(lower(p_aggregation_kind)), ''), 'custom'),
        COALESCE(p_extensions, '{}'::jsonb)
    )
    RETURNING id
    INTO v_metric_id;

    PERFORM semantic.register_metric_dependencies(
        p_view_name,
        p_metric_name,
        p_depends_on_metrics
    );

    RETURN v_metric_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.add_example(
    p_view_name text,
    p_example_name text,
    p_question text,
    p_example_sql text,
    p_context jsonb DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_example_id bigint;
BEGIN
    PERFORM semantic.assert_jsonb_type(p_context, 'object', 'context');

    IF coalesce(trim(p_example_name), '') = '' THEN
        RAISE EXCEPTION 'Example name is required.';
    END IF;

    v_view_id := semantic.require_view_id(p_view_name);

    INSERT INTO semantic.examples(
        view_id,
        name,
        question,
        example_sql,
        context
    )
    VALUES (
        v_view_id,
        p_example_name,
        p_question,
        p_example_sql,
        COALESCE(p_context, '{}'::jsonb)
    )
    RETURNING id
    INTO v_example_id;

    RETURN v_example_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.create_view(
    p_view_name text,
    p_definition jsonb
) RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_definition jsonb;
    v_item jsonb;
    v_metrics_item jsonb;
BEGIN
    IF coalesce(trim(p_view_name), '') = '' THEN
        RAISE EXCEPTION 'Semantic view name is required.';
    END IF;

    PERFORM semantic.assert_jsonb_type(p_definition, 'object', 'definition');

    v_definition := COALESCE(p_definition, '{}'::jsonb);

    IF EXISTS (SELECT 1 FROM semantic.views WHERE name = p_view_name) THEN
        RAISE EXCEPTION 'Semantic view "%" already exists.', p_view_name;
    END IF;

    PERFORM semantic.assert_jsonb_type(v_definition -> 'logical_tables', 'array', 'logical_tables');
    PERFORM semantic.assert_jsonb_type(v_definition -> 'relationships', 'array', 'relationships');
    PERFORM semantic.assert_jsonb_type(v_definition -> 'dimensions', 'array', 'dimensions');
    PERFORM semantic.assert_jsonb_type(v_definition -> 'facts', 'array', 'facts');
    PERFORM semantic.assert_jsonb_type(v_definition -> 'metrics', 'array', 'metrics');
    PERFORM semantic.assert_jsonb_type(v_definition -> 'examples', 'array', 'examples');
    PERFORM semantic.assert_jsonb_type(v_definition -> 'ai_context', 'object', 'ai_context');
    PERFORM semantic.assert_jsonb_type(v_definition -> 'options', 'object', 'options');
    PERFORM semantic.assert_jsonb_type(v_definition -> 'extensions', 'object', 'extensions');

    IF COALESCE(jsonb_array_length(COALESCE(v_definition -> 'dimensions', '[]'::jsonb)), 0) = 0
       AND COALESCE(jsonb_array_length(COALESCE(v_definition -> 'metrics', '[]'::jsonb)), 0) = 0 THEN
        RAISE EXCEPTION 'A semantic view must define at least one dimension or metric.';
    END IF;

    INSERT INTO semantic.views(
        name,
        description,
        default_base_logical_table,
        source_format,
        source_version,
        ai_context,
        options,
        extensions
    )
    VALUES (
        p_view_name,
        v_definition ->> 'description',
        v_definition ->> 'default_base_logical_table',
        COALESCE(v_definition ->> 'source_format', 'internal'),
        v_definition ->> 'source_version',
        COALESCE(v_definition -> 'ai_context', '{}'::jsonb),
        COALESCE(v_definition -> 'options', '{}'::jsonb),
        COALESCE(v_definition -> 'extensions', '{}'::jsonb)
    )
    RETURNING id
    INTO v_view_id;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(v_definition -> 'logical_tables', '[]'::jsonb))
    LOOP
        PERFORM semantic.add_logical_table(
            p_view_name,
            v_item ->> 'name',
            COALESCE(v_item ->> 'physical_table', v_item #>> '{source_mapping,physical_table}'),
            semantic.jsonb_to_text_array(v_item -> 'primary_key'),
            COALESCE(v_item -> 'unique_keys', '[]'::jsonb),
            v_item ->> 'alias',
            COALESCE(v_item ->> 'dataset_kind', 'fact'),
            COALESCE(v_item -> 'source_mapping', '{}'::jsonb),
            v_item ->> 'description',
            COALESCE(v_item -> 'extensions', '{}'::jsonb)
        );
    END LOOP;

    IF (v_definition ->> 'default_base_logical_table') IS NOT NULL THEN
        PERFORM semantic.require_logical_table_id(v_view_id, v_definition ->> 'default_base_logical_table');
    END IF;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(v_definition -> 'relationships', '[]'::jsonb))
    LOOP
        PERFORM semantic.add_relationship(
            p_view_name,
            v_item ->> 'name',
            v_item ->> 'from',
            v_item ->> 'to',
            COALESCE(v_item ->> 'join_sql', v_item ->> 'on'),
            COALESCE(v_item ->> 'cardinality', 'many_to_one'),
            v_item ->> 'description',
            COALESCE(v_item -> 'extensions', '{}'::jsonb)
        );
    END LOOP;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(v_definition -> 'dimensions', '[]'::jsonb))
    LOOP
        PERFORM semantic.add_dimension(
            p_view_name,
            v_item ->> 'table',
            v_item ->> 'name',
            COALESCE(v_item ->> 'expression_sql', v_item ->> 'sql'),
            v_item ->> 'description',
            semantic.jsonb_to_text_array(v_item -> 'synonyms'),
            v_item ->> 'data_type',
            v_item ->> 'time_granularity',
            COALESCE(v_item -> 'extensions', '{}'::jsonb)
        );
    END LOOP;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(v_definition -> 'facts', '[]'::jsonb))
    LOOP
        PERFORM semantic.add_fact(
            p_view_name,
            v_item ->> 'table',
            v_item ->> 'name',
            COALESCE(v_item ->> 'expression_sql', v_item ->> 'sql'),
            COALESCE(v_item ->> 'visibility', 'public'),
            v_item ->> 'description',
            semantic.jsonb_to_text_array(v_item -> 'synonyms'),
            v_item ->> 'data_type',
            COALESCE(v_item -> 'extensions', '{}'::jsonb)
        );
    END LOOP;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(v_definition -> 'metrics', '[]'::jsonb))
    LOOP
        PERFORM semantic.add_metric(
            p_view_name,
            v_item ->> 'table',
            v_item ->> 'name',
            COALESCE(v_item ->> 'expression_sql', v_item ->> 'sql'),
            COALESCE(v_item ->> 'visibility', 'public'),
            v_item ->> 'description',
            semantic.jsonb_to_text_array(v_item -> 'synonyms'),
            COALESCE(v_item ->> 'aggregation_kind', 'custom'),
            v_item -> 'expression_canonical',
            COALESCE(v_item ->> 'expression_language', 'postgresql_sql'),
            COALESCE(v_item -> 'extensions', '{}'::jsonb),
            NULL
        );
    END LOOP;

    FOR v_metrics_item IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(v_definition -> 'metrics', '[]'::jsonb))
    LOOP
        PERFORM semantic.register_metric_dependencies(
            p_view_name,
            v_metrics_item ->> 'name',
            semantic.jsonb_to_text_array(v_metrics_item -> 'depends_on_metrics')
        );
    END LOOP;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(v_definition -> 'examples', '[]'::jsonb))
    LOOP
        PERFORM semantic.add_example(
            p_view_name,
            v_item ->> 'name',
            v_item ->> 'question',
            v_item ->> 'sql',
            COALESCE(v_item -> 'context', '{}'::jsonb)
        );
    END LOOP;

    RETURN v_view_id;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.import_osi(
    p_model_name text,
    p_document jsonb
) RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_model_name text;
    v_definition jsonb;
    v_datasets jsonb := '[]'::jsonb;
    v_dimensions jsonb := '[]'::jsonb;
    v_facts jsonb := '[]'::jsonb;
    v_relationships jsonb := '[]'::jsonb;
    v_metrics jsonb := '[]'::jsonb;
    v_examples jsonb := '[]'::jsonb;
    v_dataset jsonb;
    v_dimension jsonb;
    v_fact jsonb;
    v_relationship jsonb;
    v_metric jsonb;
    v_example jsonb;
    v_source_table text;
BEGIN
    PERFORM semantic.assert_jsonb_type(p_document, 'object', 'document');

    v_model_name := COALESCE(NULLIF(trim(p_model_name), ''), p_document ->> 'name');

    IF coalesce(v_model_name, '') = '' THEN
        RAISE EXCEPTION 'OSI import requires a model name.';
    END IF;

    PERFORM semantic.assert_jsonb_type(p_document -> 'datasets', 'array', 'datasets');
    PERFORM semantic.assert_jsonb_type(p_document -> 'relationships', 'array', 'relationships');
    PERFORM semantic.assert_jsonb_type(p_document -> 'metrics', 'array', 'metrics');
    PERFORM semantic.assert_jsonb_type(p_document -> 'examples', 'array', 'examples');
    PERFORM semantic.assert_jsonb_type(p_document -> 'custom_extensions', 'object', 'custom_extensions');
    PERFORM semantic.assert_jsonb_type(p_document -> 'ai_context', 'object', 'ai_context');

    FOR v_dataset IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(p_document -> 'datasets', '[]'::jsonb))
    LOOP
        v_source_table := COALESCE(
            v_dataset #>> '{source,table}',
            v_dataset #>> '{source_mapping,physical_table}',
            v_dataset ->> 'physical_table',
            v_dataset ->> 'source'
        );

        v_datasets := v_datasets || jsonb_build_array(
            jsonb_build_object(
                'name', v_dataset ->> 'name',
                'physical_table', v_source_table,
                'primary_key', COALESCE(v_dataset -> 'primary_key', '[]'::jsonb),
                'unique_keys', COALESCE(v_dataset -> 'unique_keys', '[]'::jsonb),
                'alias', v_dataset ->> 'alias',
                'dataset_kind', COALESCE(v_dataset ->> 'dataset_kind', v_dataset ->> 'kind'),
                'source_mapping',
                    COALESCE(
                        v_dataset -> 'source_mapping',
                        CASE
                            WHEN jsonb_typeof(v_dataset -> 'source') = 'object' THEN v_dataset -> 'source'
                            WHEN v_source_table IS NOT NULL THEN jsonb_build_object('table', v_source_table)
                            ELSE '{}'::jsonb
                        END
                    ),
                'description', v_dataset ->> 'description',
                'extensions', COALESCE(v_dataset -> 'custom_extensions', v_dataset -> 'extensions', '{}'::jsonb)
            )
        );

        FOR v_dimension IN
            SELECT value
            FROM jsonb_array_elements(COALESCE(v_dataset -> 'dimensions', '[]'::jsonb))
        LOOP
            v_dimensions := v_dimensions || jsonb_build_array(
                jsonb_build_object(
                    'table', v_dataset ->> 'name',
                    'name', v_dimension ->> 'name',
                    'expression_sql', COALESCE(v_dimension ->> 'expression', v_dimension ->> 'sql'),
                    'description', v_dimension ->> 'description',
                    'synonyms', COALESCE(v_dimension -> 'synonyms', '[]'::jsonb),
                    'data_type', COALESCE(v_dimension ->> 'data_type', v_dimension ->> 'type'),
                    'time_granularity', v_dimension #>> '{type_params,time_granularity}',
                    'extensions', COALESCE(v_dimension -> 'custom_extensions', v_dimension -> 'extensions', '{}'::jsonb)
                )
            );
        END LOOP;

        FOR v_fact IN
            SELECT value
            FROM jsonb_array_elements(COALESCE(v_dataset -> 'facts', '[]'::jsonb))
        LOOP
            v_facts := v_facts || jsonb_build_array(
                jsonb_build_object(
                    'table', v_dataset ->> 'name',
                    'name', v_fact ->> 'name',
                    'expression_sql', COALESCE(v_fact ->> 'expression', v_fact ->> 'sql'),
                    'visibility', COALESCE(v_fact ->> 'visibility', 'public'),
                    'description', v_fact ->> 'description',
                    'synonyms', COALESCE(v_fact -> 'synonyms', '[]'::jsonb),
                    'data_type', COALESCE(v_fact ->> 'data_type', v_fact ->> 'type'),
                    'extensions', COALESCE(v_fact -> 'custom_extensions', v_fact -> 'extensions', '{}'::jsonb)
                )
            );
        END LOOP;
    END LOOP;

    FOR v_relationship IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(p_document -> 'relationships', '[]'::jsonb))
    LOOP
        v_relationships := v_relationships || jsonb_build_array(
            jsonb_build_object(
                'name', v_relationship ->> 'name',
                'from', COALESCE(v_relationship ->> 'from', v_relationship #>> '{from,dataset}'),
                'to', COALESCE(v_relationship ->> 'to', v_relationship #>> '{to,dataset}'),
                'join_sql', COALESCE(v_relationship ->> 'join_sql', v_relationship ->> 'on'),
                'cardinality', COALESCE(v_relationship ->> 'cardinality', 'many_to_one'),
                'description', v_relationship ->> 'description',
                'extensions', COALESCE(v_relationship -> 'custom_extensions', v_relationship -> 'extensions', '{}'::jsonb)
            )
        );
    END LOOP;

    FOR v_metric IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(p_document -> 'metrics', '[]'::jsonb))
    LOOP
        v_metrics := v_metrics || jsonb_build_array(
            jsonb_build_object(
                'table', COALESCE(v_metric ->> 'table', v_metric ->> 'dataset'),
                'name', v_metric ->> 'name',
                'expression_sql', COALESCE(v_metric ->> 'expression', v_metric ->> 'sql'),
                'description', v_metric ->> 'description',
                'visibility', COALESCE(v_metric ->> 'visibility', 'public'),
                'synonyms', COALESCE(v_metric -> 'synonyms', '[]'::jsonb),
                'aggregation_kind', COALESCE(v_metric ->> 'aggregation_kind', v_metric ->> 'type', 'custom'),
                'expression_canonical', COALESCE(v_metric -> 'expression_canonical', v_metric -> 'expression_ast'),
                'expression_language', COALESCE(v_metric ->> 'expression_language', 'postgresql_sql'),
                'depends_on_metrics', COALESCE(v_metric -> 'depends_on_metrics', '[]'::jsonb),
                'extensions', COALESCE(v_metric -> 'custom_extensions', v_metric -> 'extensions', '{}'::jsonb)
            )
        );
    END LOOP;

    FOR v_example IN
        SELECT value
        FROM jsonb_array_elements(COALESCE(p_document -> 'examples', '[]'::jsonb))
    LOOP
        v_examples := v_examples || jsonb_build_array(
            jsonb_build_object(
                'name', v_example ->> 'name',
                'question', v_example ->> 'question',
                'sql', COALESCE(v_example ->> 'sql', v_example ->> 'example_sql'),
                'context', COALESCE(v_example -> 'context', '{}'::jsonb)
            )
        );
    END LOOP;

    v_definition := jsonb_build_object(
        'description', p_document ->> 'description',
        'default_base_logical_table', p_document ->> 'default_base_logical_table',
        'source_format', 'osi',
        'source_version', p_document ->> 'version',
        'ai_context', COALESCE(p_document -> 'ai_context', '{}'::jsonb),
        'extensions', COALESCE(p_document -> 'custom_extensions', '{}'::jsonb),
        'logical_tables', v_datasets,
        'relationships', v_relationships,
        'dimensions', v_dimensions,
        'facts', v_facts,
        'metrics', v_metrics,
        'examples', v_examples
    );

    RETURN semantic.create_view(v_model_name, v_definition);
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.export_osi(
    p_model_name text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_view_id bigint;
    v_document jsonb;
BEGIN
    v_view_id := semantic.require_view_id(p_model_name);

    SELECT jsonb_build_object(
        'name', v.name,
        'description', v.description,
        'version', v.source_version,
        'ai_context', v.ai_context,
        'custom_extensions', v.extensions,
        'datasets',
            COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'name', lt.name,
                            'alias', lt.table_alias,
                            'dataset_kind', lt.dataset_kind,
                            'source', COALESCE(NULLIF(lt.source_mapping, '{}'::jsonb), jsonb_build_object('table', lt.physical_table::text)),
                            'primary_key', lt.primary_key_columns,
                            'unique_keys', lt.unique_key_sets,
                            'description', lt.description,
                            'custom_extensions', lt.extensions,
                            'dimensions',
                                COALESCE(
                                    (
                                        SELECT jsonb_agg(
                                            jsonb_build_object(
                                                'name', d.name,
                                                'expression', d.expression_sql,
                                                'description', d.description,
                                                'synonyms', d.synonyms,
                                                'data_type', d.data_type,
                                                'type_params',
                                                    CASE
                                                        WHEN d.time_granularity IS NOT NULL THEN
                                                            jsonb_build_object('time_granularity', d.time_granularity)
                                                        ELSE
                                                            '{}'::jsonb
                                                    END,
                                                'custom_extensions', d.extensions
                                            )
                                            ORDER BY d.name
                                        )
                                        FROM semantic.dimensions d
                                        WHERE d.view_id = lt.view_id
                                          AND d.logical_table_id = lt.id
                                    ),
                                    '[]'::jsonb
                                ),
                            'facts',
                                COALESCE(
                                    (
                                        SELECT jsonb_agg(
                                            jsonb_build_object(
                                                'name', f.name,
                                                'expression', f.expression_sql,
                                                'description', f.description,
                                                'synonyms', f.synonyms,
                                                'data_type', f.data_type,
                                                'visibility', f.visibility,
                                                'custom_extensions', f.extensions
                                            )
                                            ORDER BY f.name
                                        )
                                        FROM semantic.facts f
                                        WHERE f.view_id = lt.view_id
                                          AND f.logical_table_id = lt.id
                                    ),
                                    '[]'::jsonb
                                )
                        )
                        ORDER BY lt.name
                    )
                    FROM semantic.logical_tables lt
                    WHERE lt.view_id = v.id
                ),
                '[]'::jsonb
            ),
        'relationships',
            COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'name', r.name,
                            'from', jsonb_build_object('dataset', from_lt.name),
                            'to', jsonb_build_object('dataset', to_lt.name),
                            'join_sql', r.join_sql,
                            'cardinality', r.cardinality,
                            'description', r.description,
                            'custom_extensions', r.extensions
                        )
                        ORDER BY r.name
                    )
                    FROM semantic.relationships r
                    JOIN semantic.logical_tables from_lt ON from_lt.id = r.from_table_id
                    JOIN semantic.logical_tables to_lt ON to_lt.id = r.to_table_id
                    WHERE r.view_id = v.id
                ),
                '[]'::jsonb
            ),
        'metrics',
            COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'name', m.name,
                            'dataset', lt.name,
                            'expression', m.expression_sql,
                            'expression_ast', m.expression_canonical,
                            'expression_language', m.expression_language,
                            'description', m.description,
                            'synonyms', m.synonyms,
                            'visibility', m.visibility,
                            'aggregation_kind', m.aggregation_kind,
                            'depends_on_metrics',
                                COALESCE(
                                    (
                                        SELECT jsonb_agg(dep_metric.name ORDER BY dep_metric.name)
                                        FROM semantic.metric_dependencies md
                                        JOIN semantic.metrics dep_metric
                                          ON dep_metric.id = md.depends_on_metric_id
                                        WHERE md.metric_id = m.id
                                    ),
                                    '[]'::jsonb
                                ),
                            'custom_extensions', m.extensions
                        )
                        ORDER BY m.name
                    )
                    FROM semantic.metrics m
                    LEFT JOIN semantic.logical_tables lt ON lt.id = m.logical_table_id
                    WHERE m.view_id = v.id
                ),
                '[]'::jsonb
            ),
        'examples',
            COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'name', e.name,
                            'question', e.question,
                            'sql', e.example_sql,
                            'context', e.context
                        )
                        ORDER BY e.name
                    )
                    FROM semantic.examples e
                    WHERE e.view_id = v.id
                ),
                '[]'::jsonb
            )
    )
    INTO v_document
    FROM semantic.views v
    WHERE v.id = v_view_id;

    RETURN v_document;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.compile_sql(
    p_semantic_view text,
    p_metrics text[] DEFAULT NULL,
    p_dimensions text[] DEFAULT NULL,
    p_filters jsonb DEFAULT '{}'::jsonb
) RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
    v_view_id bigint;
    v_root_table_id bigint;
    v_root_alias text;
    v_root_table regclass;
    v_default_root_name text;
    v_select_items text[] := ARRAY[]::text[];
    v_group_items text[] := ARRAY[]::text[];
    v_where_items text[] := ARRAY[]::text[];
    v_required_table_ids bigint[] := ARRAY[]::bigint[];
    v_discovered_table_ids bigint[] := ARRAY[]::bigint[];
    v_metric_name text;
    v_dimension_name text;
    v_filter_name text;
    v_filter_spec jsonb;
    v_operator text;
    v_predicate text;
    v_in_values text;
    v_sql text;
    v_missing_table_ids bigint[];
    v_dimension_record record;
    v_metric_record record;
    v_filter_record record;
    v_tree_record record;
BEGIN
    IF p_metrics IS NULL AND p_dimensions IS NULL THEN
        RAISE EXCEPTION 'compile_sql requires at least one metric or dimension.';
    END IF;

    PERFORM semantic.assert_jsonb_type(p_filters, 'object', 'filters');

    v_view_id := semantic.require_view_id(p_semantic_view);

    SELECT default_base_logical_table
    INTO v_default_root_name
    FROM semantic.views
    WHERE id = v_view_id;

    FOREACH v_dimension_name IN ARRAY COALESCE(p_dimensions, ARRAY[]::text[]) LOOP
        SELECT d.name,
               d.expression_sql,
               d.logical_table_id
        INTO v_dimension_record
        FROM semantic.dimensions d
        WHERE d.view_id = v_view_id
          AND d.name = v_dimension_name;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Dimension "%" does not exist in semantic view "%".', v_dimension_name, p_semantic_view;
        END IF;

        v_select_items := v_select_items || format('%s AS %I', v_dimension_record.expression_sql, v_dimension_record.name);
        v_group_items := v_group_items || v_dimension_record.expression_sql;
        v_required_table_ids := array_append(v_required_table_ids, v_dimension_record.logical_table_id);
    END LOOP;

    FOREACH v_metric_name IN ARRAY COALESCE(p_metrics, ARRAY[]::text[]) LOOP
        SELECT m.name,
               m.expression_sql,
               m.logical_table_id,
               m.visibility
        INTO v_metric_record
        FROM semantic.metrics m
        WHERE m.view_id = v_view_id
          AND m.name = v_metric_name;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Metric "%" does not exist in semantic view "%".', v_metric_name, p_semantic_view;
        END IF;

        IF v_metric_record.visibility = 'private' THEN
            RAISE EXCEPTION 'Metric "%" is private and cannot be queried directly.', v_metric_name;
        END IF;

        IF v_metric_record.logical_table_id IS NULL THEN
            RAISE EXCEPTION 'Derived metric "%" is registered but direct compilation for derived metrics is not implemented in this prototype.', v_metric_name;
        END IF;

        v_select_items := v_select_items || format('%s AS %I', v_metric_record.expression_sql, v_metric_record.name);
        v_required_table_ids := array_append(v_required_table_ids, v_metric_record.logical_table_id);
    END LOOP;

    FOR v_filter_name, v_filter_spec IN
        SELECT key, value
        FROM jsonb_each(COALESCE(p_filters, '{}'::jsonb))
    LOOP
        PERFORM semantic.assert_jsonb_type(v_filter_spec, 'object', format('filter for %s', v_filter_name));

        SELECT object_kind,
               expression_sql,
               logical_table_id,
               visibility
        INTO v_filter_record
        FROM (
            SELECT 'dimension'::text AS object_kind,
                   d.expression_sql,
                   d.logical_table_id,
                   'public'::text AS visibility
            FROM semantic.dimensions d
            WHERE d.view_id = v_view_id
              AND d.name = v_filter_name
            UNION ALL
            SELECT 'fact'::text AS object_kind,
                   f.expression_sql,
                   f.logical_table_id,
                   f.visibility
            FROM semantic.facts f
            WHERE f.view_id = v_view_id
              AND f.name = v_filter_name
        ) candidates
        LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Filter "%" does not match a dimension or fact in semantic view "%".', v_filter_name, p_semantic_view;
        END IF;

        IF v_filter_record.visibility = 'private' THEN
            RAISE EXCEPTION 'Fact "%" is private and cannot be used in filters.', v_filter_name;
        END IF;

        v_required_table_ids := array_append(v_required_table_ids, v_filter_record.logical_table_id);

        v_operator := NULL;

        IF v_filter_spec ? 'eq' THEN
            v_operator := 'eq';
            v_predicate := format('%s = %L', v_filter_record.expression_sql, v_filter_spec ->> 'eq');
        ELSIF v_filter_spec ? 'neq' THEN
            v_operator := 'neq';
            v_predicate := format('%s <> %L', v_filter_record.expression_sql, v_filter_spec ->> 'neq');
        ELSIF v_filter_spec ? 'gt' THEN
            v_operator := 'gt';
            v_predicate := format('%s > %L', v_filter_record.expression_sql, v_filter_spec ->> 'gt');
        ELSIF v_filter_spec ? 'gte' THEN
            v_operator := 'gte';
            v_predicate := format('%s >= %L', v_filter_record.expression_sql, v_filter_spec ->> 'gte');
        ELSIF v_filter_spec ? 'lt' THEN
            v_operator := 'lt';
            v_predicate := format('%s < %L', v_filter_record.expression_sql, v_filter_spec ->> 'lt');
        ELSIF v_filter_spec ? 'lte' THEN
            v_operator := 'lte';
            v_predicate := format('%s <= %L', v_filter_record.expression_sql, v_filter_spec ->> 'lte');
        ELSIF v_filter_spec ? 'like' THEN
            v_operator := 'like';
            v_predicate := format('%s LIKE %L', v_filter_record.expression_sql, v_filter_spec ->> 'like');
        ELSIF v_filter_spec ? 'ilike' THEN
            v_operator := 'ilike';
            v_predicate := format('%s ILIKE %L', v_filter_record.expression_sql, v_filter_spec ->> 'ilike');
        ELSIF v_filter_spec ? 'in' THEN
            v_operator := 'in';
            PERFORM semantic.assert_jsonb_type(v_filter_spec -> 'in', 'array', format('in filter for %s', v_filter_name));
            SELECT string_agg(format('%L', value), ', ')
            INTO v_in_values
            FROM jsonb_array_elements_text(v_filter_spec -> 'in') AS t(value);

            v_predicate := format('%s IN (%s)', v_filter_record.expression_sql, COALESCE(v_in_values, 'NULL'));
        END IF;

        IF v_operator IS NULL THEN
            RAISE EXCEPTION 'Unsupported filter operator for "%". Supported operators are eq, neq, gt, gte, lt, lte, like, ilike, and in.', v_filter_name;
        END IF;

        v_where_items := v_where_items || v_predicate;
    END LOOP;

    SELECT array_agg(DISTINCT required_table_id)
    INTO v_required_table_ids
    FROM unnest(v_required_table_ids) AS t(required_table_id);

    IF COALESCE(cardinality(v_required_table_ids), 0) = 0 THEN
        RAISE EXCEPTION 'No semantic objects were selected for compilation.';
    END IF;

    IF v_default_root_name IS NOT NULL THEN
        SELECT id
        INTO v_root_table_id
        FROM semantic.logical_tables
        WHERE view_id = v_view_id
          AND name = v_default_root_name;
    END IF;

    IF v_root_table_id IS NULL THEN
        v_root_table_id := v_required_table_ids[1];
    END IF;

    SELECT table_alias, physical_table
    INTO v_root_alias, v_root_table
    FROM semantic.logical_tables
    WHERE id = v_root_table_id;

    v_discovered_table_ids := ARRAY[v_root_table_id];

    v_sql := format('SELECT%s  %s%sFROM %s AS %I',
        E'\n',
        array_to_string(v_select_items, ',' || E'\n  '),
        E'\n',
        v_root_table::text,
        v_root_alias
    );

    FOR v_tree_record IN
        WITH RECURSIVE walk AS (
            SELECT lt.id AS table_id,
                   NULL::bigint AS parent_table_id,
                   NULL::bigint AS relationship_id,
                   0 AS depth,
                   ARRAY[lt.id] AS visited
            FROM semantic.logical_tables lt
            WHERE lt.id = v_root_table_id

            UNION ALL

            SELECT next_edge.next_table_id AS table_id,
                   walk.table_id AS parent_table_id,
                   next_edge.relationship_id,
                   walk.depth + 1 AS depth,
                   walk.visited || next_edge.next_table_id
            FROM walk
            JOIN LATERAL (
                SELECT r.id AS relationship_id,
                       CASE
                           WHEN r.from_table_id = walk.table_id THEN r.to_table_id
                           ELSE r.from_table_id
                       END AS next_table_id
                FROM semantic.relationships r
                WHERE r.view_id = v_view_id
                  AND (r.from_table_id = walk.table_id OR r.to_table_id = walk.table_id)
            ) AS next_edge ON TRUE
            WHERE NOT next_edge.next_table_id = ANY(walk.visited)
        ),
        tree AS (
            SELECT DISTINCT ON (table_id)
                   table_id,
                   parent_table_id,
                   relationship_id,
                   depth
            FROM walk
            ORDER BY table_id, depth, relationship_id
        )
        SELECT tree.table_id,
               tree.parent_table_id,
               tree.relationship_id,
               tree.depth,
               child.table_alias,
               child.physical_table::text AS physical_table_name,
               rel.join_sql
        FROM tree
        JOIN semantic.logical_tables child
          ON child.id = tree.table_id
        LEFT JOIN semantic.relationships rel
          ON rel.id = tree.relationship_id
        WHERE tree.table_id <> v_root_table_id
        ORDER BY tree.depth, tree.table_id
    LOOP
        v_discovered_table_ids := array_append(v_discovered_table_ids, v_tree_record.table_id);
        v_sql := v_sql || format(
            '%sLEFT JOIN %s AS %I ON %s',
            E'\n',
            v_tree_record.physical_table_name,
            v_tree_record.table_alias,
            v_tree_record.join_sql
        );
    END LOOP;

    SELECT array_agg(required_id)
    INTO v_missing_table_ids
    FROM unnest(v_required_table_ids) AS missing(required_id)
    WHERE NOT required_id = ANY(v_discovered_table_ids);

    IF v_missing_table_ids IS NOT NULL THEN
        RAISE EXCEPTION 'Selected semantic objects are not connected by the relationship graph in semantic view "%".', p_semantic_view;
    END IF;

    IF COALESCE(cardinality(v_where_items), 0) > 0 THEN
        v_sql := v_sql || E'\nWHERE ' || array_to_string(v_where_items, ' AND ');
    END IF;

    IF COALESCE(cardinality(v_group_items), 0) > 0 THEN
        v_sql := v_sql || E'\nGROUP BY ' || array_to_string(v_group_items, ', ');
    END IF;

    RETURN v_sql;
END;
$function$;

CREATE OR REPLACE FUNCTION semantic.query(
    p_semantic_view text,
    p_metrics text[] DEFAULT NULL,
    p_dimensions text[] DEFAULT NULL,
    p_filters jsonb DEFAULT '{}'::jsonb
) RETURNS SETOF record
LANGUAGE plpgsql
AS $function$
DECLARE
    v_sql text;
BEGIN
    v_sql := semantic.compile_sql(
        p_semantic_view,
        p_metrics,
        p_dimensions,
        p_filters
    );

    RETURN QUERY EXECUTE v_sql;
END;
$function$;

CREATE VIEW semantic.meta_views AS
SELECT
    v.name AS view_name,
    v.description,
    v.default_base_logical_table,
    v.source_format,
    v.source_version,
    v.ai_context,
    v.options,
    v.extensions,
    v.created_at
FROM semantic.views v;

CREATE VIEW semantic.meta_logical_tables AS
SELECT
    v.name AS view_name,
    lt.name AS logical_table_name,
    lt.table_alias,
    lt.physical_table::text AS physical_table,
    lt.dataset_kind,
    lt.primary_key_columns,
    lt.unique_key_sets,
    lt.source_mapping,
    lt.description,
    lt.extensions,
    lt.created_at
FROM semantic.logical_tables lt
JOIN semantic.views v
  ON v.id = lt.view_id;

CREATE VIEW semantic.meta_relationships AS
SELECT
    v.name AS view_name,
    r.name AS relationship_name,
    from_lt.name AS from_logical_table,
    to_lt.name AS to_logical_table,
    r.join_sql,
    r.cardinality,
    r.description,
    r.extensions,
    r.created_at
FROM semantic.relationships r
JOIN semantic.views v
  ON v.id = r.view_id
JOIN semantic.logical_tables from_lt
  ON from_lt.id = r.from_table_id
JOIN semantic.logical_tables to_lt
  ON to_lt.id = r.to_table_id;

CREATE VIEW semantic.meta_dimensions AS
SELECT
    v.name AS view_name,
    lt.name AS logical_table_name,
    d.name AS dimension_name,
    d.expression_sql,
    d.description,
    d.synonyms,
    d.data_type,
    d.time_granularity,
    d.extensions,
    d.created_at
FROM semantic.dimensions d
JOIN semantic.views v
  ON v.id = d.view_id
JOIN semantic.logical_tables lt
  ON lt.id = d.logical_table_id;

CREATE VIEW semantic.meta_facts AS
SELECT
    v.name AS view_name,
    lt.name AS logical_table_name,
    f.name AS fact_name,
    f.expression_sql,
    f.description,
    f.synonyms,
    f.data_type,
    f.visibility,
    f.extensions,
    f.created_at
FROM semantic.facts f
JOIN semantic.views v
  ON v.id = f.view_id
JOIN semantic.logical_tables lt
  ON lt.id = f.logical_table_id;

CREATE VIEW semantic.meta_metrics AS
SELECT
    v.name AS view_name,
    lt.name AS logical_table_name,
    m.name AS metric_name,
    m.expression_sql,
    m.expression_canonical,
    m.expression_language,
    m.description,
    m.synonyms,
    m.visibility,
    m.aggregation_kind,
    m.extensions,
    m.created_at
FROM semantic.metrics m
JOIN semantic.views v
  ON v.id = m.view_id
LEFT JOIN semantic.logical_tables lt
  ON lt.id = m.logical_table_id;

CREATE VIEW semantic.meta_examples AS
SELECT
    v.name AS view_name,
    e.name AS example_name,
    e.question,
    e.example_sql,
    e.context,
    e.created_at
FROM semantic.examples e
JOIN semantic.views v
  ON v.id = e.view_id;
