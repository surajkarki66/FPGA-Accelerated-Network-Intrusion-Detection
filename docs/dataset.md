# UNSW-NB15 Dataset (`dataset/`)

## 1. Role

Training, evaluation, quantisation, and full-corpus golden generation require
the official UNSW-NB15 **training** and **testing** CSV partitions. CSVs are
**not** redistributed in this repository; obtain them from the authors and
place them under `dataset/` with the exact names expected by
`sw/model/config.py`.

See also: [architecture.md](architecture.md) (preprocessing),
[simulation.md](simulation.md) (golden generation),
[software.md](software.md).  
`make ci-smoke` avoids this dependency with synthetic INT8 vectors.

## 2. Citation and terms

[UNSW-NB15 research page](https://research.unsw.edu.au/projects/unsw-nb15-dataset)
(Moustafa & Slay). Comply with the authors’ terms of use and cite
appropriately.

## 3. Download

1. Open the distribution folder:
   [UNSW-NB15 dataset (SharePoint)](https://unsw-my.sharepoint.com/personal/z5025758_ad_unsw_edu_au/_layouts/15/onedrive.aspx?id=%2Fpersonal%2Fz5025758%5Fad%5Funsw%5Fedu%5Fau%2FDocuments%2FUNSW%2DNB15%20dataset&ga=1)
2. Download the training and testing CSV sets used by this project.
3. Copy them as:

```
dataset/UNSW_NB15_training-set.csv
dataset/UNSW_NB15_testing-set.csv
```

## 4. Expected layout

```
dataset/
  README.md                          # short pointer to this document
  .gitkeep
  UNSW_NB15_training-set.csv         # user-provided
  UNSW_NB15_testing-set.csv          # user-provided
```

Large CSVs remain untracked; only documentation and `.gitkeep` are versioned.

## 5. Path configuration

`sw/model/config.py` sets `TRAIN_CSV` / `TEST_CSV` to the paths above.
Renaming files without updating config breaks train and golden generation.

## 6. Next steps

```bash
make train && make eval && make deploy
make golden && make sim
```
