EXTENSION = pg_semantic_view
DATA = sql/pg_semantic_view--0.1.0.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
