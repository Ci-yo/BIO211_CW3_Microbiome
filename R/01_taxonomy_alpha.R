rm(list = ls())
options(stringsAsFactors = FALSE)
Sys.setenv("VROOM_CONNECTION_SIZE" = 5e6)
need_pkgs <- c("tidyverse", "vegan")
new_pkgs  <- need_pkgs[!(need_pkgs %in% installed.packages()[, "Package"])]
if (length(new_pkgs) > 0) {
  install.packages(new_pkgs)
}


library(tidyverse)
library(vegan)

data_dir <- "data"
species_file   <- file.path(data_dir, "species_table.txt")
metadata_file  <- file.path(data_dir, "metadata.txt")
pollutant_file <- file.path(data_dir, "pollutant.txt")

species_df <- readr::read_tsv(species_file)
metadata_df <- readr::read_tsv(metadata_file)
pollutant_df <- readr::read_tsv(pollutant_file)


cat("species_df:\n")
glimpse(species_df)
cat("\nmetadata_df:\n")
glimpse(metadata_df)
cat("\npollutant_df:\n")
glimpse(pollutant_df)

colnames(species_df)[1]
species_df <- species_df %>%
  rename(Sample = 1)
colnames(species_df)[1:5]

cat("\n样本是否全部在 metadata 里？\n")
all(species_df$Sample %in% metadata_df$Sample)
cat("样本是否全部在 pollutant 里？\n")
all(metadata_df$Sample %in% pollutant_df$Sample)


meta_full <- metadata_df %>%
  left_join(pollutant_df, by = "Sample")
cat("\n合并后的 meta_full:\n")
glimpse(meta_full)


## 1A. 计算每个样本的相对丰度，并变成长表 ----------------
species_rel_long <- species_df %>%
  mutate(total_count = rowSums(across(-Sample))) %>%
  mutate(across(
    .cols = -c(Sample, total_count),
    .fns  = ~ .x / total_count
  )) %>%
  select(-total_count) %>%
  pivot_longer(
    cols      = -Sample,
    names_to  = "Species",
    values_to = "RelAbundance"
  )
species_rel_long %>% 
  glimpse()


## 1B. 计算全数据的平均相对丰度，选出 top10 物种 ---------------------

species_mean <- species_rel_long %>%
  group_by(Species) %>%
  summarise(
    mean_rel = mean(RelAbundance, na.rm = TRUE),
    .groups  = "drop"
  ) %>%
  arrange(desc(mean_rel))
top10_species <- species_mean %>%
  slice_head(n = 10) %>%
  pull(Species)

top10_species


## 1C. 生成一个分组后的物种变量：10 个具体物种 + 1 个合并类 ----
library(stringr)  # string 相关函数，如果没加载可以再 library 一下
species_rel_long <- species_rel_long %>%
  mutate(
    Species_grouped = case_when(
      # 如果属于 top10 且 名字不含 unclassified/unknown/unassigned，就保留原名
      Species %in% top10_species &
        !str_detect(Species, regex("unclassified|unknown|unassigned", ignore_case = TRUE)) ~ Species,
      
      # 其它情况都归到合并类
      TRUE ~ "Minor/unclassified"
    )
  )

# 看看现在有多少类（应该是 <= 11 个）
species_rel_long %>%
  count(Species_grouped, sort = TRUE)


## 1D. 把 Cutotype 等元数据合并进来 -------------------------------

plot_df <- species_rel_long %>%
  left_join(metadata_df, by = "Sample") %>%
  # 确保 Cutotype 是 factor，有利于分面
  mutate(
    Cutotype = factor(Cutotype)
  )

# 为了让 stacked bar 的顺序更有意义，我们按平均丰度排序物种
species_order <- plot_df %>%
  group_by(Species_grouped) %>%
  summarise(
    mean_rel = mean(RelAbundance, na.rm = TRUE),
    .groups  = "drop"
  ) %>%
  arrange(desc(mean_rel)) %>%
  pull(Species_grouped)

plot_df <- plot_df %>%
  mutate(
    Species_grouped = factor(Species_grouped, levels = species_order)
  )

# 对样本做一个排序，让同一 Cutotype 的样本挨在一起
plot_df <- plot_df %>%
  arrange(Cutotype, City, Sample) %>%  # City 在 metadata 里应该有
  mutate(
    Sample = factor(Sample, levels = unique(Sample))
  )


## 1E. 画 stacked bar chart，按 Cutotype 分面 ----------------------

library(ggplot2)
tax_bar_plot <- ggplot(
  plot_df,
  aes(x = Sample, y = RelAbundance, fill = Species_grouped)
) +
  geom_col(width = 0.9) +
  facet_wrap(~ Cutotype, scales = "free_x") +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 1)
  ) +
  labs(
    x = "Sample",
    y = "Relative abundance",
    fill = "Species"
  ) +
  theme_bw() +
  theme(
    axis.text.x        = element_blank(),   # 样本太多就不显示名字了
    axis.ticks.x       = element_blank(),
    panel.grid.major.x = element_blank()
  )
tax_bar_plot



# 1）PDF（矢量图，最适合真正出版或打印）
ggsave(
  filename = "figure/Figure1_nocolor-tax_bar_plot.pdf",
  plot     = tax_bar_plot,
  width    = 8,      # 单位是英寸，大约 20 cm
  height   = 4,      # 可以按你喜好略调
  device   = cairo_pdf,
  dpi=1086
)

# 2）PNG（给 Word 报告用，高分辨率位图）
ggsave(
  filename = "figure/Figure1_nocolor-tax_bar_plot.png",
  plot     = tax_bar_plot,
  width    = 8,
  height   = 4,
  dpi      = 600     
)

library(ggplot2)
library(scales)

plot_df2 <- plot_df %>%
  mutate(RelAbundance_pct = RelAbundance * 100)
tax_bar_plot <- ggplot(
  plot_df2,
  aes(x = Sample, y = RelAbundance_pct, fill = Species_grouped)
) +
  geom_col(width = 0.9) +
  facet_wrap(~ Cutotype, nrow = 2, scales = "free_x") +
  scale_y_continuous(
    breaks = seq(0, 100, 25),
    labels = function(x) paste0(x, "%"),
    expand = c(0, 0)
  ) +
  scale_fill_brewer(palette = "Paired") +
  labs(
    x   = "Sample",
    y   = "Relative abundance (%)",
    fill = "Species"
  ) +
  theme_classic(base_size = 12) +
  theme(
    axis.text.x        = element_blank(),
    axis.ticks.x       = element_blank(),
    panel.spacing      = unit(0.4, "lines"),
    strip.background   = element_rect(fill = "white", colour = "black", linewidth = 0.8),
    strip.text         = element_text(face = "bold")
  )
tax_bar_plot

# 1）PDF（矢量图，最适合真正出版或打印）
ggsave(
  filename = "figure/Figure1-no-1086.pdf",
  plot     = tax_bar_plot,
  width    = 8,      # 单位是英寸，大约 20 cm
  height   = 4,      # 可以按你喜好略调
  device   = cairo_pdf,
  dpi=1086
)

# 2）PNG（给 Word 报告用，高分辨率位图）
ggsave(
  filename = "figure/Figure1_taxonomic_barplot.png",
  plot     = tax_bar_plot,
  width    = 8,
  height   = 4,
  dpi      = 600     
)





library(maaslin3)
library(dplyr)
library(tibble)
## 1.B1 物种计数表：把第一列 Sample 设成行名，去掉这一列
species_df <- species_df %>%
  rename(Sample = 1)          # 确保第一列名字叫 Sample

species_counts <- species_df %>%
  column_to_rownames("Sample")  # 行名 = Sample，剩下都是物种计数

## 1.B2 元数据表：只保留需要的列，并设成行名
meta_for_maaslin <- metadata_df %>%
  select(Sample, City, Cutotype, Age) %>%
  column_to_rownames("Sample")

## 1.B3 把变量类型处理好：City / Cutotype 作为因子，Age 数值型
meta_for_maaslin <- meta_for_maaslin %>%
  mutate(
    City     = factor(City,
                      levels = c("Baoding", "Dalian")),      # 第一项是参考水平
    Cutotype = factor(Cutotype,
                      levels = c("Cutotype 1", "Cutotype 2")),
    Age      = as.numeric(Age)
  )

## 1.B4 确认两个表的样本完全对齐（保险起见）
common_samples <- intersect(rownames(species_counts),
                            rownames(meta_for_maaslin))
length(common_samples)        # 应该是 120

species_counts   <- species_counts[common_samples, ]
meta_for_maaslin <- meta_for_maaslin[common_samples, ]


## 建一个输出文件夹名（会自动创建）
output_dir <- "results_maaslin3"

fit_maaslin3 <- maaslin3(
  input_data   = species_counts,
  input_metadata = meta_for_maaslin,
  output       = output_dir,
  ## 关键：模型公式
  formula      = "~ City + Cutotype + Age",
  ## 常用设置（和官方示例一致）
  normalization = "TSS",
  transform     = "LOG",
  standardize   = TRUE,
  ## 下面这些可以先用默认，也写上更清楚
  min_abundance  = 0.0,
  min_prevalence = 0.1,
  max_significance = 0.25,      # 画 summary_plot 的阈值，先放宽一点
  median_comparison_abundance  = TRUE,
  median_comparison_prevalence = FALSE,
  max_pngs = 300,
  cores    = 1,                 # 你本机就用 1 核就行
  save_models = FALSE
)



maaslin_res_all <- read.delim(
  file.path(output_dir, "all_results.tsv"),
  sep = "\t", stringsAsFactors = FALSE
)

# 看一下有哪些列名
colnames(maaslin_res_all)
head(maaslin_res_all)

library(dplyr)
library(tibble)
library(ggplot2)
## 只看 abundance 模型，且是我们关心的三个自变量
res_abund <- maaslin_res_all %>%
  filter(model == "abundance",
         metadata %in% c("City", "Cutotype", "Age"))

## 1.B1）City：q 值最小的 2 个物种 -------------------------------
res_city <- res_abund %>%
  filter(metadata == "City") %>%
  arrange(qval_individual)

city_top2 <- res_city %>%
  slice_head(n = 2)

city_top2   # 看看是哪两个物种、coef 和 q

## 1.B2）Cutotype：q 值最小的 2 个物种 --------------------------
res_cutotype <- res_abund %>%
  filter(metadata == "Cutotype") %>%
  arrange(qval_individual)

cutotype_top2 <- res_cutotype %>%
  slice_head(n = 2)

cutotype_top2

## 1.B3）Age：最强正相关 + 最强负相关各 1 个 --------------------
res_age <- res_abund %>%
  filter(metadata == "Age") %>%
  filter(!is.na(coef))

age_pos <- res_age %>%
  arrange(qval_individual, desc(coef)) %>%  # 先显著，再看系数方向
  slice_head(n = 1)

age_neg <- res_age %>%
  arrange(qval_individual, coef) %>%
  slice_head(n = 1)

age_pos
age_neg

## Age：2 个最显著正相关 + 2 个最显著负相关 -------------------------

res_age <- res_abund %>%
  filter(metadata == "Age") %>%
  filter(!is.na(coef))

age_pos_top2 <- res_age %>%
  arrange(qval_individual, desc(coef)) %>%  # 先按 q，从小到大，再看系数方向
  slice_head(n = 2)

age_neg_top2 <- res_age %>%
  arrange(qval_individual, coef) %>%        # 先按 q，从小到大，再从最负开始
  slice_head(n = 2)

age_pos_top2
age_neg_top2


## 相对丰度 + metadata 合在一起
abund_meta <- species_rel_long %>%
  left_join(metadata_df, by = "Sample") %>%
  mutate(RelAbundance_pct = RelAbundance * 100)

## 给物种加上“带 coef 和 q 的标签”
city_labels <- city_top2 %>%
  mutate(
    Species_label = paste0(
      feature,
      "\ncoef = ", round(coef, 3),
      ", q = ", signif(qval_individual, 2)
    )
  ) %>%
  select(Species = feature, Species_label)

## 把标签合并到丰度表
city_plot_df <- abund_meta %>%
  filter(Species %in% city_labels$Species) %>%
  left_join(city_labels, by = "Species")

City_boxplot <- ggplot(
  city_plot_df,
  aes(x = City, y = RelAbundance_pct)
) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.2, alpha = 0.4, size = 0.8) +
  facet_wrap(~ Species_label, scales = "free_y") +
  labs(
    x = "City",
    y = "Relative abundance (%)"
  ) +
  theme_bw(base_size = 11) +
  theme(
    axis.text.x  = element_text(angle = 45, hjust = 1),
    panel.spacing = unit(0.6, "lines")
  )

City_boxplot


cutotype_labels <- cutotype_top2 %>%
  mutate(
    Species_label = paste0(
      feature,
      "\ncoef = ", round(coef, 3),
      ", q = ", signif(qval_individual, 2)
    )
  ) %>%
  select(Species = feature, Species_label)

cutotype_plot_df <- abund_meta %>%
  filter(Species %in% cutotype_labels$Species) %>%
  left_join(cutotype_labels, by = "Species")

Cutotype_boxplot <- ggplot(
  cutotype_plot_df,
  aes(x = Cutotype, y = RelAbundance_pct)
) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.2, alpha = 0.4, size = 0.8) +
  facet_wrap(~ Species_label, scales = "free_y") +
  labs(
    x = "Cutotype",
    y = "Relative abundance (%)"
  ) +
  theme_bw(base_size = 11) +
  theme(
    axis.text.x  = element_text(angle = 0, hjust = 0.5),
    panel.spacing = unit(0.6, "lines")
  )

Cutotype_boxplot

age_labels <- bind_rows(age_pos, age_neg) %>%
  mutate(
    Species_label = paste0(
      feature,
      "\ncoef = ", round(coef, 3),
      ", q = ", signif(qval_individual, 2)
    )
  ) %>%
  select(Species = feature, Species_label)

age_plot_df <- abund_meta %>%
  filter(Species %in% age_labels$Species) %>%
  left_join(age_labels, by = "Species")

Age_scatter <- ggplot(
  age_plot_df,
  aes(x = Age, y = RelAbundance_pct)
) +
  geom_point(alpha = 0.5, size = 1.2) +
  geom_smooth(method = "lm", se = TRUE, linewidth = 0.6) +
  facet_wrap(~ Species_label, scales = "free_y") +
  labs(
    x = "Age (years)",
    y = "Relative abundance (%)"
  ) +
  theme_bw(base_size = 11)

Age_scatter



## 生成带 coef + q 的标签（4 个物种）

age_labels <- bind_rows(age_pos_top2, age_neg_top2) %>%
  mutate(
    Species_label = paste0(
      feature,
      "\ncoef = ", round(coef, 3),
      ", q = ", signif(qval_individual, 2)
    )
  ) %>%
  select(Species = feature, Species_label)

age_plot_df <- abund_meta %>%
  filter(Species %in% age_labels$Species) %>%
  left_join(age_labels, by = "Species")

Age_scatter_pretty <- ggplot(
  age_plot_df,
  aes(x = Age, y = RelAbundance_pct, colour = City)
) +
  geom_point(size = 2, alpha = 0.8) +
  geom_smooth(
    method    = "lm",
    se        = TRUE,
    linewidth = 0.7,
    colour    = "black"
  ) +
  facet_wrap(~ Species_label, scales = "free_y") +
  scale_color_brewer(palette = "Set2") +
  labs(
    x = "Age (years)",
    y = "Relative abundance (%)",
    colour = "City"
  ) +
  theme_classic(base_size = 12) +
  theme(
    strip.background = element_rect(fill = "white", colour = "black", linewidth = 0.6),
    strip.text       = element_text(face = "bold"),
    panel.spacing    = unit(0.7, "lines")
  )

Age_scatter_pretty


##colorful-figure
library(ggplot2)
library(RColorBrewer)

## City：漂亮版 boxplot ---------------------------------------------
City_boxplot_pretty <- ggplot(
  city_plot_df,
  aes(x = City, y = RelAbundance_pct)
) +
  geom_boxplot(
    aes(fill = City),
    outlier.shape = NA,
    alpha = 0.6,
    colour = "black"
  ) +
  geom_jitter(
    aes(color = City),
    width  = 0.15,
    size   = 2,
    alpha  = 0.8
  ) +
  facet_wrap(~ Species_label, scales = "free_y") +
  scale_fill_brewer(palette = "Pastel1") +
  scale_color_brewer(palette = "Set2") +
  labs(
    x = "City",
    y = "Relative abundance (%)"
  ) +
  theme_classic(base_size = 12) +
  theme(
    strip.background = element_rect(fill = "white", colour = "black", linewidth = 0.6),
    strip.text       = element_text(face = "bold"),
    axis.text.x      = element_text(angle = 45, hjust = 1),
    panel.spacing    = unit(0.7, "lines"),
    legend.position  = "none"
  )

City_boxplot_pretty

## Cutotype：漂亮版 boxplot ----------------------------------------
Cutotype_boxplot_pretty <- ggplot(
  cutotype_plot_df,
  aes(x = Cutotype, y = RelAbundance_pct)
) +
  geom_boxplot(
    aes(fill = Cutotype),
    outlier.shape = NA,
    alpha = 0.6,
    colour = "black"
  ) +
  geom_jitter(
    aes(color = Cutotype),
    width  = 0.15,
    size   = 2,
    alpha  = 0.8
  ) +
  facet_wrap(~ Species_label, scales = "free_y") +
  scale_fill_brewer(palette = "Pastel1") +
  scale_color_brewer(palette = "Set2") +
  labs(
    x = "Cutotype",
    y = "Relative abundance (%)"
  ) +
  theme_classic(base_size = 12) +
  theme(
    strip.background = element_rect(fill = "white", colour = "black", linewidth = 0.6),
    strip.text       = element_text(face = "bold"),
    axis.text.x      = element_text(angle = 0, hjust = 0.5),
    panel.spacing    = unit(0.7, "lines"),
    legend.position  = "none"
  )

Cutotype_boxplot_pretty
## Age：漂亮版散点 + 回归线 ----------------------------------------
Age_scatter_pretty <- ggplot(
  age_plot_df,
  aes(x = Age, y = RelAbundance_pct, colour = City)
) +
  geom_point(size = 2, alpha = 0.8) +
  geom_smooth(
    method    = "lm",
    se        = TRUE,
    linewidth = 0.7,
    colour    = "black"
  ) +
  facet_wrap(~ Species_label, scales = "free_y") +
  scale_color_brewer(palette = "Set2") +
  labs(
    x = "Age (years)",
    y = "Relative abundance (%)",
    colour = "City"
  ) +
  theme_classic(base_size = 12) +
  theme(
    strip.background = element_rect(fill = "white", colour = "black", linewidth = 0.6),
    strip.text       = element_text(face = "bold"),
    panel.spacing    = unit(0.7, "lines")
  )

Age_scatter_pretty


ggsave("figure/Figure2_City_boxplots.png", City_boxplot_pretty,
       width = 7, height = 4, dpi = 600)
ggsave("figure/Figure3_Cutotype_boxplots.png", Cutotype_boxplot_pretty,
       width = 7, height = 4, dpi = 600)
ggsave("figure/Figure4_Age_scatter.png", Age_scatter_pretty,
       width = 7, height = 4, dpi = 600)
# City（Figure 2）
ggsave(
  filename = "PDF-figure/Figure2_City_boxplots.pdf",
  plot     = City_boxplot_pretty,
  width    = 7,       # 英寸，大约 18 cm 宽
  height   = 5,       # 你现在这个长宽比差不多
  device   = cairo_pdf
)

# Cutotype（Figure 3）
ggsave(
  filename = "PDF-figure/Figure3_Cutotype_boxplots.pdf",
  plot     = Cutotype_boxplot_pretty,
  width    = 7,
  height   = 5,
  device   = cairo_pdf
)

# Age（Figure 4）
ggsave(
  filename = "PDF-figure/Figure4_Age_scatter.pdf",
  plot     = Age_scatter_pretty,
  width    = 7,
  height   = 5,
  device   = cairo_pdf
)




## 2(a) ----------------------------------------
library(tidyverse)

## 0. 先定义哪些列是 PAHs -----------------------------------------
# pollutant_df 已经在环境里
pah_vars <- c(
  "Acenaphtylene", "Acenaphtene", "Fluorene",
  "Phenanthrene", "Anthracene", "Fluoranthene", "Pyrene",
  "Benzo[a]anthracene", "Chrysene",
  "Benzo[b]fluoranthene", "Benzo[k]fluoranthene",
  "Benzo[a]pyrene", "Indeno[1,2,3-cd]pyrene",
  "Dibenzo[a,h]anthracene", "Benzo[ghi]perylene"
)
# Nicotine / Cotinine 不是 PAH，所以没放进来

## 1. 合并相对丰度和 PAH，变成长表 -------------------------------

abund_pah_long <- species_rel_long %>%
  left_join(pollutant_df, by = "Sample") %>%
  pivot_longer(
    cols      = all_of(pah_vars),
    names_to  = "PAH",
    values_to = "PAH_conc"
  )

# 可选，看看结构
abund_pah_long %>% glimpse()

## 2. 对每个 Species × PAH 做 Spearman 相关 -----------------------

cor_results <- abund_pah_long %>%
  group_by(Species, PAH) %>%
  summarise(
    n = sum(!is.na(RelAbundance) & !is.na(PAH_conc)),
    rho = suppressWarnings(
      cor(RelAbundance, PAH_conc,
          method = "spearman",
          use    = "complete.obs")
    ),
    pval = suppressWarnings(
      cor.test(RelAbundance, PAH_conc,
               method = "spearman")$p.value
    ),
    .groups = "drop"
  ) %>%
  mutate(
    qval = p.adjust(pval, method = "BH")
  )

cor_results %>% head()


## 3. 每个 PAH 选 q 值最小的物种，做成表 ---------------------------

pah_summary <- cor_results %>%
  filter(!is.na(qval)) %>%
  group_by(PAH) %>%
  arrange(qval) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  arrange(qval)

pah_summary_table <- pah_summary %>%
  select(
    PAH,
    Species,
    rho,
    pval,
    qval,
    n
  )

pah_summary_table

if (!dir.exists("results")) dir.create("results")

readr::write_tsv(
  pah_summary_table,
  "results/Q2a_PAH_species_cor_summary.tsv"
)

## 4. 从 summary table 选出 q 值最小的 5 对 -----------------------

top5_pairs <- pah_summary %>%
  arrange(qval) %>%
  slice_head(n = 5) %>%
  mutate(
    PairLabel = paste0(
      Species, " vs ", PAH,
      "\nρ = ", round(rho, 3),
      ", q = ", signif(qval, 2)
    )
  )

top5_pairs

## 5. 把 top5 的信息合并回长表，准备画图 --------------------------

top5_plot_df <- abund_pah_long %>%
  semi_join(top5_pairs, by = c("Species", "PAH")) %>%
  left_join(
    top5_pairs %>% select(Species, PAH, PairLabel),
    by = c("Species", "PAH")
  ) %>%
  mutate(
    RelAbundance_pct = RelAbundance * 100
  )

library(ggplot2)

PAH_scatter <- ggplot(
  top5_plot_df,
  aes(x = PAH_conc, y = RelAbundance_pct)
) +
  geom_point(alpha = 0.7, size = 2) +
  geom_smooth(
    method    = "lm",
    se        = TRUE,
    linewidth = 0.7,
    colour    = "black"
  ) +
  facet_wrap(~ PairLabel, scales = "free") +
  labs(
    x = "PAH concentration",
    y = "Relative abundance (%)"
  ) +
  theme_classic(base_size = 12) +
  theme(
    strip.background = element_rect(fill = "white", colour = "black", linewidth = 0.6),
    strip.text       = element_text(face = "bold"),
    panel.spacing    = unit(0.7, "lines")
  )

PAH_scatter

ggsave(
  filename = "figure/Figure5_PAH_top5_scatter.pdf",
  plot     = PAH_scatter,
  width    = 7,
  height   = 5,
  device   = cairo_pdf
)

ggsave(
  filename = "figure/Figure5_PAH_top5_scatter.png",
  plot     = PAH_scatter,
  width    = 7,
  height   = 5,
  dpi      = 600
)

library(ggplot2)

PAH_scatter_color <- ggplot(
  top5_plot_df,
  aes(x = PAH_conc, y = RelAbundance_pct)
) +
  geom_point(alpha = 0.8, size = 2,
             colour = "#1b9e77") +   # 绿色系，比纯灰好看
  geom_smooth(
    method    = "lm",
    se        = TRUE,
    linewidth = 0.7,
    colour    = "black"
  ) +
  facet_wrap(~ PairLabel, scales = "free", ncol = 3) +
  labs(
    x = "PAH concentration",
    y = "Relative abundance (%)"
  ) +
  theme_classic(base_size = 11) +
  theme(
    panel.border     = element_rect(colour = "black", fill = NA, linewidth = 0.5),
    panel.spacing    = unit(0.8, "lines"),
    strip.background = element_rect(fill = "white", colour = "black", linewidth = 0.5),
    strip.text       = element_text(face = "bold", size = 9),
    axis.text        = element_text(size = 9),
    axis.title       = element_text(size = 11)
  )

PAH_scatter_color

abund_pah_long <- species_rel_long %>%
  left_join(pollutant_df, by = "Sample") %>%
  left_join(metadata_df %>% select(Sample, City, Cutotype),
            by = "Sample") %>%
  pivot_longer(
    cols      = all_of(pah_vars),
    names_to  = "PAH",
    values_to = "PAH_conc"
  )

# 记得用新的 abund_pah_long 重新生成 top5_plot_df
top5_plot_df <- abund_pah_long %>%
  semi_join(top5_pairs, by = c("Species", "PAH")) %>%
  left_join(
    top5_pairs %>% select(Species, PAH, PairLabel),
    by = c("Species", "PAH")
  ) %>%
  mutate(RelAbundance_pct = RelAbundance * 100)
PAH_scatter_city <- ggplot(
  top5_plot_df,
  aes(x = PAH_conc, y = RelAbundance_pct, colour = City)
) +
  geom_point(alpha = 0.8, size = 2) +
  geom_smooth(
    method    = "lm",
    se        = TRUE,
    linewidth = 0.7,
    colour    = "black"
  ) +
  facet_wrap(~ PairLabel, scales = "free", ncol = 3) +
  scale_color_brewer(palette = "Set2") +
  labs(
    x = "PAH concentration",
    y = "Relative abundance (%)",
    colour = "City"
  ) +
  theme_classic(base_size = 11) +
  theme(
    panel.border     = element_rect(colour = "black", fill = NA, linewidth = 0.5),
    panel.spacing    = unit(0.8, "lines"),
    strip.background = element_rect(fill = "white", colour = "black", linewidth = 0.5),
    strip.text       = element_text(face = "bold", size = 9),
    axis.text        = element_text(size = 9),
    axis.title       = element_text(size = 11)
  )

PAH_scatter_city
ggsave(
  filename = "figure/Figure5_PAH_top5_scatter_color.png",
  plot     = PAH_scatter_color,
  width    = 8,
  height   = 5,
  dpi      = 600
)
ggsave(
  filename = "figure/Figure5_PAH_top5_scatter_city.png",
  plot     = PAH_scatter_city,
  width    = 8,
  height   = 5,
  dpi      = 600
)


## 3(a) Rarefaction curve -----------------------------------------
library(tidyverse)
library(vegan)

## 1. 准备计数矩阵
species_counts <- species_df %>%
  as_tibble() %>%
  column_to_rownames("Sample") %>%  # 如果第一列不是 Sample，对应改一下
  as.matrix()

## 每个样本的测序深度
lib_size <- rowSums(species_counts)
summary(lib_size)

## 2. 设定一串要看的 rarefaction 深度（从 1000 到最小测序深度）
min_depth <- min(lib_size)
max_depth <- max(lib_size)

# 为了图好看，不要太多点，可以取 8–10 个深度
depth_seq <- unique(round(seq(500, min_depth, length.out = 10)))

depth_seq

## 3. 对每个 depth，用 rrarefy 子抽样并算 Shannon ----------------
set.seed(123)  # 固定随机数种子，结果可重复

rare_list <- lapply(depth_seq, function(d) {
  rare_counts <- rrarefy(species_counts, sample = d)
  data.frame(
    Sample  = rownames(rare_counts),
    Depth   = d,
    Shannon = diversity(rare_counts, index = "shannon")
  )
})

rare_curve_df <- bind_rows(rare_list)

## 如果想按 Cutotype 上色，可以 merge metadata
rare_curve_df <- rare_curve_df %>%
  left_join(
    metadata_df %>% select(Sample, Cutotype),
    by = "Sample"
  )

## 4. 选择一个 rarefaction depth（这里先用最小测序深度）
rare_depth <- min_depth   # 这样可以保留所有样本

## 5. 画 rarefaction 曲线 + 虚线 -------------------------------
library(ggplot2)
library(grid)

rare_curve_plot <- ggplot(
  rare_curve_df,
  aes(x = Depth,
      y = Shannon,
      group  = Sample,
      colour = Cutotype)      # ★ 按 Cutotype 上色
) +
  geom_line(alpha = 0.4) +    # 线稍微清晰一点
  geom_vline(
    xintercept = rare_depth,
    linetype   = "dashed",
    linewidth  = 0.7,
    colour     = "black"      # ★ 虚线用黑色
  ) +
  scale_colour_brewer(palette = "Set2") +  # ★ 好看的配色
  labs(
    x = "Sequencing depth (rarefied reads)",
    y = "Shannon diversity",
    colour = "Cutotype"
  ) +
  theme_classic(base_size = 11) +
  theme(
    panel.border  = element_rect(colour = "black",
                                 fill   = NA,
                                 linewidth = 0.5),
    panel.spacing = unit(0.5, "lines")
  )

rare_curve_plot


ggsave(
  "figure/Figure6_rarefaction_curve.pdf",
  rare_curve_plot,
  width  = 7,
  height = 5,
  device = cairo_pdf
)

ggsave(
  "figure/Figure6_rarefaction_curve.png",
  rare_curve_plot,
  width  = 7,
  height = 5,
  dpi    = 600
)




## 3(b) 计算 alpha 多样性（Shannon + Richness） -------------------

set.seed(123)
species_rare <- rrarefy(species_counts, sample = rare_depth)

alpha_df <- data.frame(
  Sample   = rownames(species_rare),
  Shannon  = diversity(species_rare, index = "shannon"),
  Richness = specnumber(species_rare)
) %>%
  left_join(metadata_df, by = "Sample")

alpha_df %>% head()

alpha_df <- alpha_df %>%
  mutate(
    evenness = Shannon / log(Richness)  # Pielou’s evenness, 和课件一样的思路
  )

## Violin plot: Shannon vs Cutotype --------------------------------
## 先确保 Cutotype 是有顺序的 factor（可选）
alpha_df$Cutotype <- factor(alpha_df$Cutotype,
                            levels = c("Cutotype 1", "Cutotype 2"))

alpha_violin <- ggplot(alpha_df,
                       aes(x = Cutotype,
                           y = Shannon,
                           fill = Cutotype)) +      # ★ 用 fill 映射 Cutotype
  geom_violin(
    trim   = FALSE,
    alpha  = 0.7,
    colour = NA
  ) +
  # ★ 叠加 boxplot（白底细边）
  geom_boxplot(
    width        = 0.18,
    outlier.shape = NA,
    fill         = "white",
    colour       = "black",
    linewidth    = 0.4
  ) +
  # ★ 再叠加 jitter 点，按 Cutotype 上色
  geom_jitter(
    aes(color = Cutotype),
    width  = 0.08,
    size   = 1.6,
    alpha  = 0.8
  ) +
  # ★ 手动指定颜色（你要别的颜色也可以改）
  scale_fill_manual(values = c("Cutotype 1" = "#F4A6A6",
                               "Cutotype 2" = "#A6C6F4")) +
  scale_color_manual(values = c("Cutotype 1" = "#D26464",
                                "Cutotype 2" = "#4A7DC1")) +
  labs(
    x = "Cutotype",
    y = "Shannon diversity"
  ) +
  theme_classic(base_size = 11) +
  theme(
    panel.border    = element_rect(colour = "black",
                                   fill   = NA,
                                   linewidth = 0.5),
    legend.position = "none"      # 不需要 legend 就关掉
  )

alpha_violin


ggsave(
  "figure/Figure7_Shannon_by_Cutotype.pdf",
  alpha_violin,
  width  = 6,
  height = 4.5,
  device = cairo_pdf
)

ggsave(
  "figure/Figure7_Shannon_by_Cutotype.png",
  alpha_violin,
  width  = 6,
  height = 4.5,
  dpi    = 600
)

## 3(c) ANOVA: City, Cutotype, Age 对 alpha 多样性的影响 ---------
library(tidyverse)
## Q-Q plots for alpha diversity metrics ---------------------------

library(tidyverse)
library(ggplot2)

alpha_long <- alpha_df %>%
  select(Sample, evenness, Richness, Shannon) %>%
  pivot_longer(
    cols      = c(evenness, Richness, Shannon),
    names_to  = "metric",
    values_to = "value"
  )
alpha_long_all <- alpha_df %>%
  select(Sample, evenness, Richness, Shannon) %>%
  pivot_longer(
    cols      = c(evenness, Richness, Shannon),
    names_to  = "alpha",
    values_to = "value"
  ) %>%
  filter(value > 0)

## 2) Alpha diversity 密度图（和老师那张一样的结构） -----------------
densityPlot <- ggplot(alpha_long_all, aes(x = value, fill = alpha)) +
  geom_density(alpha = 0.5) +
  facet_wrap(~ alpha, scales = "free") +
  theme_minimal() +
  labs(
    title = "Alpha Diversity Density Plot",
    x     = "Value",
    y     = "Density"
  ) +
  theme(legend.position = "none")

densityPlot


qq_plot <- ggplot(alpha_long, aes(sample = value)) +
  stat_qq(size = 1) +
  stat_qq_line() +
  facet_wrap(~ metric, scales = "free") +
  labs(
    title = "Q-Q Plots of Alpha Diversity Metrics",
    x     = "Theoretical Quantiles",
    y     = "Sample Quantiles"
  ) +
  theme_classic(base_size = 11) +
  theme(
    plot.title   = element_text(hjust = 0.5, face = "bold"),
    panel.border = element_rect(colour = "black", fill = NA, linewidth = 0.4)
  )

qq_plot

if (!dir.exists("figure")) dir.create("figure")

ggsave(
  filename = "figure/Figure8_alpha_QQplots.pdf",
  plot     = qq_plot,
  width    = 8,
  height   = 4,
  device   = cairo_pdf
)

ggsave(
  filename = "figure/Figure8_alpha_QQplots.png",
  plot     = qq_plot,
  width    = 8,
  height   = 4,
  dpi      = 600
)

## 先把 alpha 数据转成长表
alpha_long <- alpha_df %>%
  select(Sample, richness, Shannon, evenness) %>%
  pivot_longer(
    cols      = c(evenness, richness, Shannon),
    names_to  = "metric",
    values_to = "value"
  )


## 画 Q-Q 图
qq_plot <- ggplot(alpha_long, aes(sample = value)) +
  stat_qq(size = 1) +
  stat_qq_line() +
  facet_wrap(~ metric, scales = "free") +
  labs(
    title = "Q-Q Plots of Alpha Diversity Metrics",
    x     = "Theoretical Quantiles",
    y     = "Sample Quantiles"
  ) +
  theme_classic(base_size = 11) +
  theme(
    plot.title   = element_text(hjust = 0.5, face = "bold"),
    panel.border = element_rect(colour = "black", fill = NA, linewidth = 0.4)
  )

qq_plot

## 保存（高分辨率）
if (!dir.exists("figure")) dir.create("figure")

ggsave(
  filename = "figure/Figure6_alpha_QQplots.pdf",
  plot     = qq_plot,
  width    = 8,
  height   = 4,
  device   = cairo_pdf
)

ggsave(
  filename = "figure/Figure6_alpha_QQplots.png",
  plot     = qq_plot,
  width    = 8,
  height   = 4,
  dpi      = 600
)

alpha_df <- alpha_df %>%
  mutate(
    City     = factor(City),
    Cutotype = factor(Cutotype),
    Age      = as.numeric(Age)
  )

anova_mod <- aov(Shannon ~ City + Cutotype + Age, data = alpha_df)
anova_summary <- summary(anova_mod)[[1]]
anova_summary

## 4. Beta-diversity analysis --------------------------------

library(tidyverse)
library(vegan)
library(ggplot2)

## 1. 准备数据 ---------------------------------------------------------
# species_counts: Q3 里已经建好的计数矩阵 (rows = Sample, cols = Species)
# metadata_df   : 包含 Sample, City, Cutotype, Age 等信息

meta_beta <- metadata_df %>%
  mutate(
    City     = factor(City),
    Cutotype = factor(Cutotype),
    Age      = as.numeric(Age)
  ) %>%
  arrange(Sample)

# 确保行名与 metadata 的 Sample 顺序一致
species_counts <- species_counts[meta_beta$Sample, ]

## 2. 计算 Bray–Curtis 和 binary Jaccard 距离 -------------------------

# Bray–Curtis：定量，考虑丰度
bray_dist <- vegdist(species_counts, method = "bray")

# binary Jaccard：先转 presence/absence，再算定性距离
species_pa   <- 1 * (species_counts > 0)
jaccard_dist <- vegdist(species_pa, method = "jaccard")

## 3. PERMANOVA（后面 4b 要用） ---------------------------------------

set.seed(123)

bray_perm <- adonis2(
  bray_dist ~ City + Cutotype + Age,
  data        = meta_beta,
  permutations = 999,
  by          = "margin"   # 或 "term"
)

jaccard_perm <- adonis2(
  jaccard_dist ~ City + Cutotype + Age,
  data        = meta_beta,
  permutations = 999,
  by          = "margin"
)

bray_perm
jaccard_perm

## 4. Bray–Curtis 的 PCoA + 作图 --------------------------------------

bray_pcoa <- cmdscale(bray_dist, k = 2, eig = TRUE)

bray_scores <- data.frame(
  Sample = rownames(bray_pcoa$points),
  PCoA1  = bray_pcoa$points[, 1],
  PCoA2  = bray_pcoa$points[, 2],
  row.names = NULL
) %>%
  left_join(meta_beta, by = "Sample")

bray_eigs <- eigenvals(bray_pcoa)
bray_var1 <- 100 * signif(bray_eigs[1] / sum(bray_eigs), 2)
bray_var2 <- 100 * signif(bray_eigs[2] / sum(bray_eigs), 2)

bray_xlab <- paste0("PCoA1 (variance explained: ", bray_var1, "%)")
bray_ylab <- paste0("PCoA2 (variance explained: ", bray_var2, "%)")

bray_pcoa_plot <- ggplot(
  bray_scores,
  aes(x = PCoA1, y = PCoA2, colour = Cutotype)
) +
  stat_ellipse(
    aes(fill = Cutotype),
    geom  = "polygon",
    type  = "t",
    level = 0.95,
    alpha = 0.15,
    colour = NA,
    show.legend = FALSE
  ) +
  geom_point(size = 2.8, alpha = 0.9) +
  scale_colour_manual(values = c("Cutotype 1" = "#F4A8A8",
                                 "Cutotype 2" = "#99BDEB")) +
  scale_fill_manual(values = c("Cutotype 1" = "#F4A8A8",
                               "Cutotype 2" = "#99BDEB")) +
  labs(x = bray_xlab, y = bray_ylab) +
  theme_classic(base_size = 11) +
  theme(
    panel.border = element_rect(colour = "black", fill = NA, linewidth = 0.5),
    legend.position = "right"
  )

bray_pcoa_plot

ggsave(
  "figure/Figure9_PCoA_BrayCutotype.png",
  bray_pcoa_plot, width = 6.5, height = 4.8, dpi = 600
)

## 5. Jaccard 的 PCoA + 作图 -----------------------------------------

jaccard_pcoa <- cmdscale(jaccard_dist, k = 2, eig = TRUE)

jaccard_scores <- data.frame(
  Sample = rownames(jaccard_pcoa$points),
  PCoA1  = jaccard_pcoa$points[, 1],
  PCoA2  = jaccard_pcoa$points[, 2],
  row.names = NULL
) %>%
  left_join(meta_beta, by = "Sample")

jaccard_eigs <- eigenvals(jaccard_pcoa)
jaccard_var1 <- 100 * signif(jaccard_eigs[1] / sum(jaccard_eigs), 2)
jaccard_var2 <- 100 * signif(jaccard_eigs[2] / sum(jaccard_eigs), 2)

jac_xlab <- paste0("PCoA1 (variance explained: ", jaccard_var1, "%)")
jac_ylab <- paste0("PCoA2 (variance explained: ", jaccard_var2, "%)")

jaccard_pcoa_plot <- ggplot(
  jaccard_scores,
  aes(x = PCoA1, y = PCoA2, colour = Cutotype)
) +
  stat_ellipse(
    aes(fill = Cutotype),
    geom  = "polygon",
    type  = "t",
    level = 0.95,
    alpha = 0.15,
    colour = NA,
    show.legend = FALSE
  ) +
  geom_point(size = 2.8, alpha = 0.9) +
  scale_colour_manual(values = c("Cutotype 1" = "#F4A8A8",
                                 "Cutotype 2" = "#99BDEB")) +
  scale_fill_manual(values = c("Cutotype 1" = "#F4A8A8",
                               "Cutotype 2" = "#99BDEB")) +
  labs(x = jac_xlab, y = jac_ylab) +
  theme_classic(base_size = 11) +
  theme(
    panel.border = element_rect(colour = "black", fill = NA, linewidth = 0.5),
    legend.position = "right"
  )

jaccard_pcoa_plot

ggsave(
  "figure/Figure10_PCoA_JaccardCutotype.png",
  jaccard_pcoa_plot, width = 6.5, height = 4.8, dpi = 600
)
bray_perm_tbl    <- as.data.frame(bray_perm)
jaccard_perm_tbl <- as.data.frame(jaccard_perm)

bray_perm_tbl
jaccard_perm_tbl


library(tidyverse)
library(viridis)

## 1) 构建 OTUTable：Sample × Species × RelativeAbundance(%) ----
#（结构等价于 Lab 里的 OTUTable）
OTUTable <- species_rel_long %>%
  mutate(RelativeAbundance = RelAbundance * 100) %>%
  select(Sample, Species, RelativeAbundance)

## 2) 选一批要画在 heatmap 里的优势物种 ----
# 这里用你之前算好的 species_mean，取前 11 个（想改成前 10、前 15 都可以）
species_order <- species_mean %>%
  slice_head(n = 11) %>%
  pull(Species)

## 3) 填补 Sample × Species 组合，缺失的相对丰度设为 0 ----
df2_full <- OTUTable %>%
  filter(Species %in% species_order) %>%
  tidyr::complete(
    Sample,
    Species = species_order,
    fill = list(RelativeAbundance = 0)
  )

# y 轴上物种的顺序
df2_full$Species <- factor(df2_full$Species, levels = species_order)

## （可选推荐）按 Cutotype + City 排序 sample，让热图更有结构感 ----
sample_order <- metadata_df %>%
  select(Sample, City, Cutotype) %>%
  distinct() %>%
  arrange(Cutotype, City, Sample) %>%
  pull(Sample)

df2_full <- df2_full %>%
  mutate(Sample = factor(Sample, levels = sample_order))

## 4) 画 heatmap  ----
Plot_Heatmap <- ggplot(
  df2_full,
  aes(x = Sample, y = Species, fill = RelativeAbundance)
) +
  geom_tile() +
  scale_fill_viridis(option = "plasma", direction = 1) +
  theme_classic(base_size = 11) +
  labs(
    x     = "Sample",
    y     = "Species",
    fill  = "Relative\nabundance (%)",
    title = "Heatmap of dominant species across samples"
  ) +
  theme(
    axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1),
    strip.text  = element_text(size = 10, face = "bold")
  )

Plot_Heatmap

ggsave(
  "figure/Figure_heatmap_dominant_species.png",
  Plot_Heatmap,
  width  = 10,
  height = 6,
  dpi    = 600
)


