CREATE EXTENSION pg_semantic_view;

CREATE TABLE public.customers (
    id bigint PRIMARY KEY,
    region text NOT NULL,
    customer_class text NOT NULL
);

CREATE TABLE public.orders (
    id bigint PRIMARY KEY,
    customer_id bigint NOT NULL REFERENCES public.customers(id),
    order_date date NOT NULL,
    subtotal numeric(12, 2) NOT NULL,
    discount numeric(12, 2) NOT NULL
);

SELECT semantic.create_view(
    p_view_name => 'corporate_revenue',
    p_definition => jsonb_build_object(
        'description', 'Revenue model used in demo.sql',
        'default_base_logical_table', 'orders',
        'logical_tables', jsonb_build_array(
            jsonb_build_object(
                'name', 'orders',
                'physical_table', 'public.orders',
                'primary_key', jsonb_build_array('id'),
                'dataset_kind', 'fact'
            ),
            jsonb_build_object(
                'name', 'customers',
                'physical_table', 'public.customers',
                'primary_key', jsonb_build_array('id'),
                'dataset_kind', 'dimension'
            )
        ),
        'relationships', jsonb_build_array(
            jsonb_build_object(
                'name', 'orders_to_customers',
                'from', 'orders',
                'to', 'customers',
                'join_sql', 'orders.customer_id = customers.id',
                'cardinality', 'many_to_one'
            )
        ),
        'dimensions', jsonb_build_array(
            jsonb_build_object(
                'table', 'customers',
                'name', 'region',
                'sql', 'customers.region'
            ),
            jsonb_build_object(
                'table', 'customers',
                'name', 'customer_class',
                'sql', 'customers.customer_class'
            ),
            jsonb_build_object(
                'table', 'orders',
                'name', 'order_date',
                'sql', 'orders.order_date',
                'data_type', 'date',
                'time_granularity', 'day'
            )
        ),
        'metrics', jsonb_build_array(
            jsonb_build_object(
                'table', 'orders',
                'name', 'net_revenue',
                'sql', 'SUM(orders.subtotal - orders.discount)',
                'aggregation_kind', 'sum'
            ),
            jsonb_build_object(
                'table', 'orders',
                'name', 'order_count',
                'sql', 'COUNT(orders.id)',
                'aggregation_kind', 'count'
            )
        ),
        'examples', jsonb_build_array(
            jsonb_build_object(
                'name', 'revenue_by_region',
                'question', 'What is net revenue by region?',
                'sql', 'SELECT customers.region, SUM(orders.subtotal - orders.discount) AS net_revenue FROM public.orders AS orders LEFT JOIN public.customers AS customers ON orders.customer_id = customers.id GROUP BY customers.region'
            )
        )
    )
);

SELECT semantic.compile_sql(
    p_semantic_view => 'corporate_revenue',
    p_metrics => ARRAY['net_revenue', 'order_count'],
    p_dimensions => ARRAY['region'],
    p_filters => '{"region":{"eq":"EMEA"}}'::jsonb
);

SELECT *
FROM semantic.query(
    p_semantic_view => 'corporate_revenue',
    p_metrics => ARRAY['net_revenue', 'order_count'],
    p_dimensions => ARRAY['region'],
    p_filters => '{"region":{"eq":"EMEA"}}'::jsonb
) AS t(region text, net_revenue numeric, order_count bigint);
