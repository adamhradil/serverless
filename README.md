# Serverless vs IaaS Benchmark

Master's thesis project benchmarking IaaS and FaaS (serverless) architectures using an ETL pipeline on Azure.

## Requirements

- OpenTofu
- Azure CLI
- Docker
- Python 3.12+

## Setup

Fill in `.env` based on `.env.example`, then:

```sh
tofu -chdir=src/infrastructure init
export $(cat .env | xargs -I% echo TF_VAR_%) && tofu -chdir=src/infrastructure apply
```
