# This R Notebook describes the implementation of gene set enrichment analysis (GSEA) using the clusterProfiler package. For more information please see the full documentation here: https://bioconductor.org/packages/release/bioc/vignettes/clusterProfiler/inst/doc/clusterProfiler.html

if (!require("BiocManager", quietly = TRUE))
    install.packages("BiocManager")

BiocManager::install("clusterProfiler")
BiocManager::install("pathview")
BiocManager::install("enrichplot")


# Install and load required packages
```{r, message=F, warning=F}
library(clusterProfiler)
library(enrichplot)
# we use ggplot2 to add x axis labels (ex: ridgeplot)
library(ggplot2)
```

# Annotations
# I'm using *D melanogaster* data, so I install and load the annotation "org.Dm.eg.db" below. See all annotations available here: http://bioconductor.org/packages/release/BiocViews.html#___OrgDb (there are 19 presently available). 

```{r, message=F, warning=F}
# SET THE DESIRED ORGANISM HERE
organism <- "org.Mm.eg.db"
BiocManager::install(organism, character.only = TRUE)
library(organism, character.only = TRUE)
```

#Prepare Input
```{r}
# reading in data from deseq2
df <- read.csv("C:/Users/topohl/Documents/Data/neuropilvsmicroglia_log2fc.csv", header = TRUE)
# Rename the first column
colnames(df)[1] <- "gene_symbol"

# we want the log2 fold change
original_gene_list <- df$log2fc

# name the vector
names(original_gene_list) <- df$gene_symbol

# omit any NA values
gene_list <- na.omit(original_gene_list)

# sort the list in decreasing order (required for clusterProfiler)
gene_list <- sort(gene_list, decreasing = TRUE)

## Gene Set Enrichment
# Params:  
  
# **keyType** This is the source of the annotation (gene ids). The options vary for each annotation. In the example of *org.Dm.eg.db*, the options are:   
  
# "ACCNUM"       "ALIAS"        "ENSEMBL"      "ENSEMBLPROT"  "ENSEMBLTRANS" "ENTREZID"      
# "ENZYME"       "EVIDENCE"     "EVIDENCEALL"  "FLYBASE"      "FLYBASECG"    "FLYBASEPROT"   
# "GENENAME"     "GO"           "GOALL"        "MAP"          "ONTOLOGY"     "ONTOLOGYALL"   
# "PATH"         "PMID"         "REFSEQ"       "SYMBOL"       "UNIGENE"      "UNIPROT"  
  
# Check which options are available with the `keytypes` command, for example `keytypes(org.Dm.eg.db)`. 
  
# **ont** one of "BP", "MF", "CC" or "ALL"  
# **nPerm** permutation numbers, the higher the number of permutations you set, the more accurate your results is, but it will also cost longer time for running permutation.  
# **minGSSize** minimal size of each geneSet for analyzing.   
# **maxGSSize** maximal size of genes annotated for testing.   
# **pvalueCutoff** pvalue Cutoff.   
# **pAdjustMethod** one of "holm", "hochberg", "hommel", "bonferroni", "BH", "BY", "fdr", "none" 

```{r}
library(clusterProfiler)

gse <- gseGO(geneList = gene_list,
             ont = "ALL",
             keyType = "SYMBOL",
             nPerm = 10000,
             minGSSize = 3,
             maxGSSize = 800,
             pvalueCutoff = 0.05,
             verbose = TRUE,
             OrgDb = organism,
             pAdjustMethod = "none")
```

# Output
##Table of results
```{r}
head(gse)
```

##Dotplot
```{r echo=TRUE, fig.width = 15, fig.height=8}
require(DOSE)
dotplot(gse, showCategory = 10, split = ".sign") + facet_grid(. ~ .sign)
```

##Encrichment plot map:
#Enrichment map organizes enriched terms into a network with edges connecting overlapping gene sets. In this way, mutually overlapping gene sets are tend to cluster together, making it easy to identify functional modules.
```{r echo = TRUE}
library(ggplot2)
install.packages("ggnewscale")
library(ggnewscale)
similarity_matrix <- pairwise_termsim(gse)
emapplot(similarity_matrix, showCategory = 10)
# emapplot(gse, showCategory = 10)

```

##Category Netplot
#The cnetplot depicts the linkages of genes and biological concepts (e.g. GO terms or KEGG pathways) as a network (helpful to see which genes are involved in enriched pathways and genes that may belong to multiple annotation categories).
```{r fig.width = 18}
# categorySize can be either 'pvalue' or 'geneNum'
cnetplot(gse, categorySize = "pvalue", foldChange = gene_list, showCategory = 3)
```

## Ridgeplot
Helpful to interpret up/down-regulated pathways.
```{r fig.width = 18, fig.height = 12}
install.packages("ggridges")
library(ggridges)
ridgeplot(gse) + labs(x = "enrichment distribution")
```

## GSEA Plot  
Traditional method for visualizing GSEA result.  
  
Params:  
**Gene Set** Integer. Corresponds to gene set in the gse object. The first gene set is 1, second gene set is 2, etc. 

```{r fig.height=6}
# Use the `Gene Set` param for the index in the title, and as the value for geneSetId
gseaplot(gse, by = "all", title = gse$Description[1], geneSetID = 1)
```

## PubMed trend of enriched terms
Plots the number/proportion of publications trend based on the query result from PubMed Central.
```{r fig.width = 10}
install.packages("europepmc")
library(europepmc)
terms <- gse$Description[1:3]
pmcplot(terms, 2010:2018, proportion = FALSE)
```


# KEGG Gene Set Enrichment Analysis
#For KEGG pathway enrichment using the `gseKEGG()` function, we need to convert id types. We can use the `bitr` function for this (included in clusterProfiler). It is normal for this call to produce some messages / warnings. 

#In the `bitr` function, the param `fromType` should be the same as `keyType` from the `gseGO` function above (the annotation source). This param is used again in the next two steps: creating `dedup_ids` and `df2`.  

#`toType` in the `bitr` function has to be one of the available options from `keyTypes(org.Dm.eg.db)` and must map to one of 'kegg', 'ncbi-geneid', 'ncib-proteinid' or 'uniprot' because `gseKEGG()` only accepts one of these 4 options as it's `keytype` parameter. In the case of org.Dm.eg.db, none of those 4 types are available, but 'ENTREZID' are the same as ncbi-geneid for org.Dm.eg.db so we use this for `toType`. 

# As our intial input, we use `original_gene_list` which we created above.

## Prepare Input
```{r}
# Convert gene IDs for gseKEGG function
# We will lose some genes here because not all IDs will be converted
ids<-bitr(names(original_gene_list), fromType = "SYMBOL", toType = "UNIPROT", OrgDb=organism)

# remove duplicate IDS (here I use "ENSEMBL", but it should be whatever was selected as keyType)
dedup_ids = ids[!duplicated(ids[c("SYMBOL")]),]

# Create a new dataframe df2 which has only the genes which were successfully mapped using the bitr function above
df2 = df[df$gene_symbol %in% dedup_ids$SYMBOL,]

# Create a new column in df2 with the corresponding ENTREZ IDs
df2$gene_symbol = dedup_ids$UNIPROT

# Create a vector of the gene unuiverse
kegg_gene_list <- df2$log2fc

# Name vector with ENTREZ ids
names(kegg_gene_list) <- df2$gene_symbol

# omit any NA values 
kegg_gene_list<-na.omit(kegg_gene_list)

# sort the list in decreasing order (required for clusterProfiler)
kegg_gene_list = sort(kegg_gene_list, decreasing = TRUE)

```
## Create gseKEGG object
 
**organism** KEGG Organism Code: The full list is here: https://www.genome.jp/kegg/catalog/org_list.html (need the 3 letter code). I define this as `kegg_organism` first, because it is used again below when making the pathview plots.  
**nPerm** permutation numbers, the higher the number of permutations you set, the more accurate your results is, but it will also cost longer time for running permutation.  
**minGSSize** minimal size of each geneSet for analyzing.   
**maxGSSize** maximal size of genes annotated for testing.   
**pvalueCutoff** pvalue Cutoff.   
**pAdjustMethod** one of "holm", "hochberg", "hommel", "bonferroni", "BH", "BY", "fdr", "none".  
**keyType** one of 'kegg', 'ncbi-geneid', 'ncib-proteinid' or 'uniprot'.  
```{r}

library(clusterProfiler)
getOption("clusterProfiler.download.method")
install.packages("R.utils")
library(R.utils)

# Set the download method for clusterProfiler
R.utils::setOption("clusterProfiler.download.method","auto")

kegg_organism = "mmu"
kk2 <- gseKEGG(geneList     = kegg_gene_list,
               organism     = kegg_organism,
               nPerm        = 10000,
               minGSSize    = 3,
               maxGSSize    = 800,
               pvalueCutoff = 0.05,
               pAdjustMethod = "none",
               keyType       = "uniprot")
```

```{r}
head(kk2, 10)
```

## Dotplot
```{r echo=TRUE}
dotplot(kk2, showCategory = 10, title = "Enriched Pathways" , split=".sign") + facet_grid(.~.sign)
```

## Encrichment plot map:
Enrichment map organizes enriched terms into a network with edges connecting overlapping gene sets. In this way, mutually overlapping gene sets are tend to cluster together, making it easy to identify functional modules.
```{r echo=TRUE}
 emapplot(kk2)
```

## Category Netplot:
The cnetplot depicts the linkages of genes and biological concepts (e.g. GO terms or KEGG pathways) as a network (helpful to see which genes are involved in enriched pathways and genes that may belong to multiple annotation categories).
```{r fig.width=12}
# categorySize can be either 'pvalue' or 'geneNum'
cnetplot(kk2, categorySize="pvalue", foldChange=gene_list)
```

## Ridgeplot
Helpful to interpret up/down-regulated pathways.
```{r fig.width=18, fig.height=12}
ridgeplot(kk2) + labs(x = "enrichment distribution")
```

# GSEA Plot  
Traditional method for visualizing GSEA result.  
  
Params:  
**Gene Set** Integer. Corresponds to gene set in the gse object. The first gene set is 1, second gene set is 2, etc. Default: 1  

```{r fig.height=6}
# Use the `Gene Set` param for the index in the title, and as the value for geneSetId
gseaplot(kk2, by = "all", title = kk2$Description[1], geneSetID = 1)
```

#Pathview
This will create a PNG and *different* PDF of the enriched KEGG pathway.  
  
Params:  
**gene.data** This is `kegg_gene_list` created above  
**pathway.id** The user needs to enter this. Enriched pathways + the pathway ID are provided in the gseKEGG output table (above).  
**species** Same as `organism` above in `gseKEGG`, which we defined as `kegg_organism`

```{r, message=F, warning=F, echo = TRUE}
library(pathview)

# Produce the native KEGG plot (PNG)
dme <- pathview(gene.data=kegg_gene_list, pathway.id="dme04130", species = kegg_organism)

# Produce a different plot (PDF) (not displayed here)
dme <- pathview(gene.data=kegg_gene_list, pathway.id="dme04130", species = kegg_organism, kegg.native = F)
```
```{r pressure, echo=TRUE, fig.cap="KEGG Native Enriched Pathway Plot", out.width = '100%'}
knitr::include_graphics("dme04130.pathview.png")
```