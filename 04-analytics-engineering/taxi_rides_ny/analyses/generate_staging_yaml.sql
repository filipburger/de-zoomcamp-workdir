{% set models_to_generate = ['dim_zones', 'fact_trips'] %}
{{ codegen.generate_model_yaml(model_names=models_to_generate) }}