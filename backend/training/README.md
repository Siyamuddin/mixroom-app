# Producer capture training conversion

`producer_capture_converter.py` turns consented v4 capture bundles into deterministic,
sharded JSONL examples. It imports the production `mix_refine_v1` feature builder,
so every eligible apply or magnitude example contains the same 77 values used by
the backend ONNX models.

Local conversion:

```bash
python3 backend/training/producer_capture_converter.py \
  /path/to/producer_sessions \
  --output /tmp/mixroom-producer-training
```

Batch conversion directly from encrypted storage:

```bash
python3 backend/training/producer_capture_converter.py \
  s3://BUCKET/structured/ \
  --output s3://BUCKET/training-ready/run=YYYY-MM-DD/ \
  --sessions-table mixroom-producer-training-sessions-prod \
  --shard-size 10000
```

The converter streams one bundle at a time, deduplicates examples, keeps every
session in one deterministic train/validation/test split, and writes checksummed
shards plus `manifest.json`. Manual-only actions train action selection and direct
action targets. Magnitude-scale training only uses AI actions where a meaningful
proposal-to-result ratio exists. Unsupported action types remain available for
diagnosis, acceptance, and future-model objectives without contaminating the
current ONNX objectives.

Validate a converted dataset and train the two production-compatible models:

```bash
python3 backend/training/train_mix_refine_models.py \
  /tmp/mixroom-producer-training \
  --output /tmp/mixroom-models \
  --validate-only

python3 -m pip install -r backend/training/requirements.txt
python3 backend/training/train_mix_refine_models.py \
  /tmp/mixroom-producer-training \
  --output /tmp/mixroom-models
```

Training stops instead of publishing a misleading model unless the apply data
contains both accepted and rejected examples and both objectives meet their
minimum sample counts. Publishing remains an explicit review step through the
existing model publication scripts.

Check upload coverage and the 24-hour ingestion SLA before converting:

```bash
python3 backend/training/producer_training_status.py \
  --bucket mixroom-app-api-prod-producertrainingbucket-u03fpm8b5zfy \
  --sessions-table mixroom-producer-training-sessions-prod
```

The report contains aggregate counts only. It exits nonzero if fewer than 95%
of sessions older than 24 hours have reached verified ingestion.
