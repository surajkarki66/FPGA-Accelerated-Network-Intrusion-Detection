# UNSW-NB15 Dataset (`dataset/`)

Training, evaluation, and quantization require the official UNSW-NB15 **training** and **testing** CSV partitions.


## 1. Download
1. Open the distribution folder:
   [UNSW-NB15 dataset (SharePoint)](<https://unsw-my.sharepoint.com/personal/z5025758_ad_unsw_edu_au/_layouts/15/onedrive.aspx?id=%2Fpersonal%2Fz5025758%5Fad%5Funsw%5Fedu%5Fau%2FDocuments%2FUNSW%2DNB15%20dataset&ga=1>)
2. Download the training and testing CSV sets used by this project.
3. Copy them as:
```
dataset/UNSW_NB15_training-set.csv
dataset/UNSW_NB15_testing-set.csv
```

## 2. Expected layout

```
dataset/
  README.md                          # short pointer to this document
  .gitkeep
  UNSW_NB15_training-set.csv         # user-provided
  UNSW_NB15_testing-set.csv          # user-provided
```