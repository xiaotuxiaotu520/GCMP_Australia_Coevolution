library(biomformat)
library(phyloseq)
library(paleotree)
library(picante)
library(phytools)
library(MCMCglmm)
library(reshape2)
library(RColorBrewer)
library(ggplot2)
library(MASS)
library(genefilter)

mytopk <- function (k, na.rm = TRUE) {
    function(x) {
        if (na.rm) {
            x = x[!is.na(x)]
        }
        x >= sort(x, decreasing = TRUE)[k] & x > 0
    }
}


map <- import_qiime_sample_data('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/1_canonical_starting_files/gcmp16S_map_r22_with_mitochondrial_data.txt')
map[map=='Unknown'] <- NA
biom_object <- read_biom('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/12_PICRUSt/output/picrust_ko/ko_predictions.biom')
otus <- otu_table(as(biom_data(biom_object), "matrix"), taxa_are_rows = TRUE)
otu_data <- merge_phyloseq(otus,map)


rm(list=c('biom_object','otus'))
gc()

## determine set of functions that are present in at least 2 samples

hosttree <- read.tree('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/1_canonical_starting_files/host_tree_from_step_11.newick')


for(tiscomp in c('M','T','S')) {
    
    if(tiscomp == 'S') {mytk <- 30} else {mytk <- 50}
    
    m.pruned <- subset_samples(otu_data,tissue_compartment == tiscomp)
    s.pruned <- filter_taxa(m.pruned, function(x) sum(x>0)>1,T)
	pruned <- filter_taxa(s.pruned, filterfun(mytopk(mytk)),T)


    pruned.hosttree <- drop.tip(hosttree,hosttree$tip.label[!hosttree$tip.label %in% sample_data(pruned)$X16S_tree_name])

    sample_data(pruned)$X16S_tree_name[!sample_data(pruned)$X16S_tree_name %in% pruned.hosttree$tip.label] <- NA
    sample_data(pruned)$X16S_tree_name <- droplevels(sample_data(pruned)$X16S_tree_name)

    otutable <- as.matrix(as.data.frame(otu_table(pruned)))



    assocs <- melt(otutable)
    assocs <- data.frame(count=assocs$value,otu=assocs$Var1,sample=assocs$Var2)
    assocs <- merge(assocs,sample_data(pruned)[,c('X16S_tree_name','geographic_area','colony_name')],by.x='sample',by.y=0,all=F)


    inv.host.full <- inverseA(pruned.hosttree)
    inv.host <- inv.host.full$Ainv

    ancests <- vector()
    for(tip in pruned.hosttree$tip.label) {
        temp <- list()
        check <- 1
        counter <- tip
        while(check==1) {
            temp[counter] <- inv.host.full$pedigree[inv.host.full$pedigree[,'node.names']==counter,][[2]]
            counter <- temp[[length(temp)]]
            if(is.na(inv.host.full$pedigree[inv.host.full$pedigree[,'node.names']==counter,][[2]])) {check <- 0}
        }
        ancests[tip] <- paste(temp, collapse=',')
    }

    pedigree_hosts <- unique(merge(as(map,'data.frame')[,c('X16S_tree_name','field_host_name')],ancests,by.x='X16S_tree_name',by.y=0))

    dir.create('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/mcmcglmm_picrust_raw')

    write.table(pedigree_hosts,file=paste0('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/mcmcglmm_picrust_raw/',tiscomp,'_host_pedigree.txt'),sep='\t',quote=F,row.names=F)

    host.otuAS<-as(kronecker(inv.host, Diagonal(length(levels(assocs$otu)))), "dgCMatrix")  # host evolutionary effect
    rownames(host.otuAS)<-apply(expand.grid(levels(assocs$otu), rownames(inv.host)), 1, function(x){paste(x[2],x[1], sep=".")})



    ##assocs$otu																 # non-phylogenetic main effect for bacteria
    ##assocs$X16S_tree_name														 # non-phylogenetic main effect for hosts
    assocs$X16S_tree_name.phy<-assocs$X16S_tree_name       				         # phylogenetic main effect for hosts
    assocs$Host.otu<-paste(assocs$X16S_tree_name, assocs$otu, sep=".")      # non-phylogentic interaction effect
    assocs$Host.otu[is.na(assocs$X16S_tree_name)] <- NA
    assocs$Host.otu.hostphy<-paste(assocs$X16S_tree_name, assocs$otu, sep=".") # phylogentic host evolutionary effect (specifies whether abundance is determined by an interaction between non-phylogenetic otu and the phylogenetic position of the host)
    assocs$Host.otu.hostphy[is.na(assocs$X16S_tree_name)] <- NA


    assocs$geo.otu <- paste(assocs$geographic_area, assocs$otu, sep=".")


    randfacts <- c('otu','geo.otu','Host.otu.hostphy','Host.otu')



    rand <- as.formula(paste0('~ ',paste(randfacts, collapse=' + ')))



	priorC <- list(R=list(V=1, nu=0))

    ## priors for the random evolutionary effects (from Hadfield):
    phypri<-lapply(1:length(randfacts), function(x){list(V=1, nu=1, alpha.mu=0, alpha.V=1000)})

    ## combine priors:
    priorC$G<-phypri
    names(priorC$G)<-paste("G", 1:length(randfacts), sep="")

    save.image(file=paste0('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/mcmcglmm_picrust_raw/',tiscomp,'_mcmc_setup.RData'))

}

