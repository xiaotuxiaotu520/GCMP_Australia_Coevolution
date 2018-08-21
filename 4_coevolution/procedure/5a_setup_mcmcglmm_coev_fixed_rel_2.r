library(phyloseq)
library(paleotree)
library(picante)
library(phytools)
library(MCMCglmm)
library(reshape2)
library(RColorBrewer)
library(ggplot2)
library(MASS)


tissue.fams <- c('c__Chloroplast','f__Flammeovirgaceae', 'f__[Amoebophilaceae]', 'f__Cryomorphaceae', 'f__Flavobacteriaceae', 'f__Hyphomicrobiaceae', 'f__Methylobacteriaceae', 'f__Phyllobacteriaceae', 'f__Rhodobacteraceae', 'f__Rhodospirillaceae', 'f__Pelagibacteraceae', 'f__Alteromonadaceae', 'f__OM60', 'f__Endozoicimonaceae', 'f__Moraxellaceae', 'f__Piscirickettsiaceae', 'f__Vibrionaceae', 'Unassigned', 'c__Alphaproteobacteria', 'o__Kiloniellales')
skeleton.fams <- c('c__Chloroplast','f__Flammeovirgaceae', 'f__[Amoebophilaceae]', 'f__Flavobacteriaceae', 'f__Clostridiaceae', 'f__Pirellulaceae', 'f__Hyphomicrobiaceae', 'f__Methylobacteriaceae', 'f__Phyllobacteriaceae', 'f__Rhodobacteraceae', 'f__Rhodospirillaceae', 'f__Alteromonadaceae', 'f__Endozoicimonaceae', 'f__Piscirickettsiaceae', 'f__Spirochaetaceae', 'Unassigned', 'c__Alphaproteobacteria', 'o__Myxococcales')
mucus.fams <- c('c__Chloroplast','f__Flammeovirgaceae', 'f__Cryomorphaceae', 'f__Flavobacteriaceae', 'f__Synechococcaceae', 'f__Methylobacteriaceae', 'f__Rhodobacteraceae', 'f__Pelagibacteraceae', 'f__Alteromonadaceae', 'f__OM60', 'f__Endozoicimonaceae', 'f__Halomonadaceae', 'f__Moraxellaceae', 'f__Piscirickettsiaceae', 'f__Pseudoalteromonadaceae', 'Unassigned', 'c__Alphaproteobacteria')

allfams <- unique(c(tissue.fams,skeleton.fams,mucus.fams))



famlist <- list(T=allfams[!allfams %in% tissue.fams],S=allfams[!allfams %in% skeleton.fams],M=allfams[!allfams %in% mucus.fams])

compartments <- list(T='tissue',S='skeleton',M='mucus')


map <- import_qiime_sample_data('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/1_canonical_starting_files/gcmp16S_map_r25_with_mitochondrial_data.txt')
map[map=='Unknown'] <- NA
biom_object <- import_biom('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/MED_otu_table.biom')
colnames(tax_table(biom_object)) <- c('Kingdom','Phylum','Class','Order','Family','Genus','Species')

otu_data_full <- merge_phyloseq(biom_object,map)
otu_data_pruned <- prune_samples(sample_sums(otu_data_full) >= 1000, otu_data_full)
otu_data <- subset_samples(otu_data_pruned, !is.na(colony_name))

rm(list=c('biom_object','otu_data_full','otu_data_pruned'))
gc()


hosttree <- read.tree('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/1_canonical_starting_files/host_tree_from_step_11.newick')




for(compart in c('T','S','M')) {
    
    comp.pruned <- subset_samples(otu_data, tissue_compartment==compart)
    
    for(taxon in famlist[[compart]]) {
        
        dir.create(paste0('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/mcmcglmm_coevolution_2/',compartments[[compart]],'/',taxon,'/'), recursive=T)
        
        tre <- read.nexus(paste0('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/mcmcglmm_coevolution_2/',compartments[[compart]],'/',taxon,'/beast/',taxon,'_final_tree.tree'))
        
        taxon_data <- merge_phyloseq(comp.pruned,tre)
        
        sample_data(taxon_data)$sample_sum <- sample_sums(taxon_data)
        n.pruned <- prune_samples(sample_sums(taxon_data) >= 10, taxon_data)

        pruned.hosttree <- drop.tip(hosttree,hosttree$tip.label[!hosttree$tip.label %in% sample_data(n.pruned)$X16S_tree_name])

        sample_data(n.pruned)$X16S_tree_name[!sample_data(n.pruned)$X16S_tree_name %in% pruned.hosttree$tip.label] <- NA
        sample_data(n.pruned)$X16S_tree_name <- droplevels(sample_data(n.pruned)$X16S_tree_name)

        c.pruned <- prune_samples(!is.na(sample_data(n.pruned)$X16S_tree_name), n.pruned)
        pruned <- filter_taxa(c.pruned, function(x) any(x>0),TRUE)

        otutable <- as.matrix(as.data.frame(otu_table(pruned)))


        assocs <- melt(otutable,as.is=T)
        assocs <- data.frame(count=assocs$value,otu=assocs$Var1,sample=assocs$Var2)
        assocs <- merge(assocs,sample_data(pruned)[,c('X16S_tree_name','geographic_area','sample_sum','colony_name')],by.x='sample',by.y=0,all=F)


        inv.host.full <- inverseA(pruned.hosttree)
        inv.host <- inv.host.full$Ainv

        host.ancests <- vector()
        for(tip in pruned.hosttree$tip.label) {
            temp <- list()
            check <- 1
            counter <- tip
            while(check==1) {
                temp[counter] <- inv.host.full$pedigree[inv.host.full$pedigree[,'node.names']==counter,][[2]]
                counter <- temp[[length(temp)]]
                if(is.na(inv.host.full$pedigree[inv.host.full$pedigree[,'node.names']==counter,][[2]])) {check <- 0}
            }
            host.ancests[tip] <- paste(temp, collapse=',')
        }

        pedigree_hosts <- unique(merge(as(map,'data.frame')[,c('X16S_tree_name','field_host_name')],host.ancests,by.x='X16S_tree_name',by.y=0))

        write.table(pedigree_hosts,file=paste0('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/mcmcglmm_coevolution_2/',compartments[[compart]],'/',taxon,'/',taxon,'_host_pedigree.txt'),sep='\t',quote=F,row.names=F)


        pruned.bacttree <- phy_tree(pruned)
        pruned.bacttree$node.label <- NULL


        inv.bact.full <- inverseA(pruned.bacttree)
        inv.bact <- inv.bact.full$Ainv

        bact.ancests <- vector()
        for(tip in pruned.bacttree$tip.label) {
            temp <- list()
            check <- 1
            counter <- tip
            while(check==1) {
                temp[counter] <- inv.bact.full$pedigree[inv.bact.full$pedigree[,'node.names']==counter,][[2]]
                counter <- temp[[length(temp)]]
                if(is.na(inv.bact.full$pedigree[inv.bact.full$pedigree[,'node.names']==counter,][[2]])) {check <- 0}
            }
            bact.ancests[tip] <- paste(temp, collapse=',')
        }

        pedigree_bacts <- unique(merge(as(tax_table(pruned),'matrix'),bact.ancests,by=0))

        write.table(pedigree_bacts,file=paste0('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/mcmcglmm_coevolution_2/',compartments[[compart]],'/',taxon,'/',taxon,'_bact_pedigree.txt'),sep='\t',quote=F,row.names=F)







        host.otuA<-as(kronecker(inv.host, inv.bact), "dgCMatrix")                   # coevolutionary effect
        host.otuAS<-as(kronecker(inv.host, Diagonal(nrow(inv.bact))), "dgCMatrix")  # host evolutionary effect
        host.otuSA<-as(kronecker(Diagonal(nrow(inv.host)), inv.bact), "dgCMatrix")  # parasite evolutionary effect


        rownames(host.otuA)<-apply(expand.grid(rownames(inv.bact), rownames(inv.host)), 1, function(x){paste(x[2],x[1], sep=".")})
        rownames(host.otuAS)<-rownames(host.otuSA)<-rownames(host.otuA)


        ##assocs$otu																 # non-phylogenetic main effect for bacteria
        ##assocs$X16S_tree_name												 # non-phylogenetic main effect for hosts
        assocs$otu.phy<-assocs$otu                                 				     # phylogenetic main effect for bacteria
        assocs$X16S_tree_name.phy<-assocs$X16S_tree_name                   # phylogenetic main effect for hosts
        assocs$Host.otu<-paste(assocs$X16S_tree_name, assocs$otu, sep=".")      # non-phylogentic interaction effect
        assocs$Host.otu[is.na(assocs$X16S_tree_name)] <- NA
        assocs$Host.otu.cophy<-paste(assocs$X16S_tree_name, assocs$otu, sep=".")  # phylogentic coevolution effect
        assocs$Host.otu.cophy[is.na(assocs$X16S_tree_name)] <- NA
        assocs$Host.otu.hostphy<-paste(assocs$X16S_tree_name, assocs$otu, sep=".") # phylogentic host evolutionary effect (specifies whether abundance is determined by an interaction between non-phylogenetic otu and the phylogenetic position of the host)
        assocs$Host.otu.hostphy[is.na(assocs$X16S_tree_name)] <- NA
        assocs$Host.otu.otuphy<-paste(assocs$X16S_tree_name, assocs$otu, sep=".") # phylogentic parasite evolutionary effect (specifies whether abundance is determined by an interaction between non-phylogenetic host species and the phylogenetic position of the otu)
        assocs$Host.otu.otuphy[is.na(assocs$X16S_tree_name)] <- NA
        assocs$colony.otu.phy <- paste(assocs$colony_name, assocs$otu, sep=".")

        assocs$geo.otu <- paste(assocs$geographic_area, assocs$otu, sep=".")


        otu.colonySA <- as(kronecker(Diagonal(length(unique(assocs$colony_name[!is.na(assocs$colony_name)]))), inv.bact), "dgCMatrix")
        rownames(otu.colonySA)<-apply(expand.grid(rownames(inv.bact), unique(assocs$colony_name[!is.na(assocs$colony_name)])), 1, function(x){paste(x[2],x[1], sep=".")})


        randfacts <- c('otu.phy','otu','geo.otu','Host.otu.hostphy','Host.otu.otuphy','Host.otu','Host.otu.cophy')


        rand <- as.formula(paste0('~ ',paste(randfacts, collapse=' + ')))



        priorC <- list(B=list(mu=c(0,1), V=diag(c(1e+8,1e-6))), R=list(V=1, nu=0))

        ## priors for the random evolutionary effects (from Hadfield):
        phypri<-lapply(1:length(randfacts), function(x){list(V=1, nu=1, alpha.mu=0, alpha.V=1000)})

        ## combine priors:
        priorC$G<-phypri
        names(priorC$G)<-paste("G", 1:length(randfacts), sep="")

        save.image(file=paste0('/Users/Ryan/Dropbox/Selectively_Shared_Vega_Lab_Stuff/GCMP/Projects/Australia_Coevolution_Paper/16S_analysis/4_coevolution/output/mcmcglmm_coevolution_2/',compartments[[compart]],'/',taxon,'/',taxon,'_mcmc_setup.RData'))
    }
}