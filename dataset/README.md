# UNSW-NB15 dataset

Place the official CSV splits in this folder. 

## Download

1. Open the UNSW-NB15 OneDrive folder:
  [UNSW-NB15 dataset (SharePoint)](https://unsw-my.sharepoint.com/personal/z5025758_ad_unsw_edu_au/_layouts/15/onedrive.aspx?id=%2Fpersonal%2Fz5025758%5Fad%5Funsw%5Fedu%5Fau%2FDocuments%2FUNSW%2DNB15%20dataset&ga=1)
2. Download the training and testing CSV sets used by this project.
3. Copy them here with these exact names:

```
dataset/UNSW_NB15_training-set.csv
dataset/UNSW_NB15_testing-set.csv
```

Project page / citation info:  
[UNSW-NB15 research page](https://research.unsw.edu.au/projects/unsw-nb15-dataset)  
(Moustafa & Slay). Follow the dataset authors’ terms of use.

## Expected layout

```
dataset/
  README.md                          # this file
  .gitkeep
  UNSW_NB15_training-set.csv         # you download
  UNSW_NB15_testing-set.csv          # you download
```

After the files are in place:

```bash
make train
make eval
```

`sw/model/config.py` points `TRAIN_CSV` / `TEST_CSV` at these paths.
