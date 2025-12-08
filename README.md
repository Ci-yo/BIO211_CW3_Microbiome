# BIO211 Coursework 3 – Palm Skin Metagenomic Analysis

This repository contains the R code, input data and figures for my BIO211 Coursework 3 (palm skin metagenomic data analysis).

## Project overview

The dataset consists of 120 palm skin metagenomic samples with:
- a **species-level count table** (`data/species_table.tsv`)
- **sample metadata** including City, Cutotype and Age (`data/metadata.tsv`)
- **pollutant measurements** for 15 PAHs plus Nicotine and Cotinine (`data/pollutant.tsv`)

The aim of the coursework was to:

1. Characterise taxonomic composition across **Cutotype 1 vs Cutotype 2**.
2. Perform **multivariable association analysis** with MaAsLin3 (City, Cutotype, Age).
3. Study **correlations between species abundance and pollutant levels** (Spearman, FDR).
4. Analyse **alpha diversity** (rarefaction, Shannon, richness) and
5. Analyse **beta diversity** (Bray–Curtis, Jaccard, PCoA, PERMANOVA).

## Repository structure

```text
BIO211_CW3/
├── BIO211_CW3.Rproj        # RStudio project
├── R/
│   └── 01_taxonomy_alpha.R # main analysis script (Tasks 1–4)
├── data/
│   ├── metadata.tsv        # sample metadata
│   ├── pollutant.tsv       # pollutant concentrations (PAHs, Nicotine, Cotinine)
│   └── species_table.tsv   # species-level count table
├── figures/                # exported figures for the report
│   ├── Figure1_taxonomic_barplot.png
│   ├── Figure2_City_boxplots.png
│   ├── Figure3_Cutotype_boxplots.png
│   ├── Figure4_Age_scatter.png
│   ├── Figure5_PAH_top5_scatter_city.png
│   ├── Figure6_rarefaction_curve.png
│   ├── Figure7_Shannon_by_Cutotype.png
│   ├── Figure8_alpha_QQplots.png
│   ├── Figure9_PCoA_BrayCutotype.png
│   └── Figure10_PCoA_JaccardCutotype.png
└── report/
    └── BIO211_CW3_report.pdf  # final coursework report
