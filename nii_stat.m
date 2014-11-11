function nii_stat(xlsname, roiIndices, modalityIndices,numPermute, pThresh, minOverlap, regressBehav, maskName, GrayMatterConnectivityOnly, deSkew, doTFCE, doSVM)
%Analyze MAT files
% xlsname         : name of excel file where first column is mat name for
%                   participant and subsequent columns are behavioral values
% roiIndices      : [from nii_modality_list], will be numbers like 0=voxelwise,1=brodmann,2=jhu, 3=fox, 4=tpm, 5=aal
% modalityIndices : 1=lesion,2=cbf,3=rest,4=i3mT1,5=i3mT2,6=fa,7=dti
% numPermute    : -1=FDR,0=Bonferroni, else control for familywise error based on N iterations
%                  see nii_stat_core for more details
% pThresh       : 1-tailed statistical threshold
% minOverlap    : only examine voxels/regions non-zero in this many participants
% regressBehav  : (optional) if true use lesion volume to regress behavioral data
% maskName      : (optional) name of image to mask voxelwise data
% GrayMatterConnectivityOnly : (optional) if false, DTI and resting state
%                  will examine GM <-> WM, WM <-> CSF, GM <-> CSF connections
% deSkew        : Report and attempt to correct skewed behavioral data
% doTFCE        : Apply threshold-free cluster enhancement (voxelwise only)
%Examples
% nii_stat_xls
% nii_stat_xls('LIMEpf.xlsx',1,1,0,0.05,1)
% nii_stat_xls('LIMEab1.xlsx',0,1,0,0.05,1)
% nii_stat_xls('LIMEab.xlsx',[1 2],[1 2 3 4 5 6 7],2000,0.05,1)
% nii_stat_xls('LIMEab3.xlsx',[1],[1],-1000,0.05,1)
% nii_stat_xls('LIMEab1.xlsx',[2],[7],1000,0.05,1)
% nii_stat_xls('LIMEab1.xlsx',[0],[1],0,0.05,1)
if exist('spm','file') ~= 2
    error('%s requires SPM to be installed', mfilename);
end
if ~exist('xlsname','var')  
   [file,pth] = uigetfile({'*.xls;*.xlsx;*.txt;*.tab','Excel/Text file';'*.txt;*.tab','Tab-delimited text (*.tab, *.txt)';'*.val','VLSM/NPM text (*.val)'},'Select the design file'); 
   if isequal(file,0), return; end;
   xlsname=[pth file];
end
if exist(xlsname,'file') ~= 2
    error('Unable to find Excel file named %s\n',xlsname);
end
[designMat, designUsesNiiImages] = readDesign (xlsname);
[~, xlsname, ~] = fileparts(xlsname);
if ~exist('regressBehav','var')
   regressBehav = false; 
end
if ~exist('maskName','var')
   maskName = []; %no mask 
end
if ~exist('GrayMatterConnectivityOnly','var')
    GrayMatterConnectivityOnly = true;
end
if ~exist('deSkew','var')
    deSkew = false;
end
if ~exist('customROI','var')
    customROI = false;
end
if ~exist('doTFCE','var')
    doTFCE = false;
end
if ~exist('reportROIvalues','var')
    reportROIvalues = false;
end
if ~exist('numPermute','var')
   numPermute = 0; 
end
if ~exist('pThresh','var')
   pThresh = 0.05; 
end
if ~exist('minOverlap','var')
   minOverlap = 0; 
end
if ~exist('doSVM','var')
    doSVM = false;
end
[kROIs, kROInumbers] = nii_roi_list();
[~, kModalityNumbers] = nii_modality_list();
if ~exist('modalityIndices','var') %have user manually specify settings
    prompt = {'Number of permutations (-1 for FDR, 0 for Bonferroni, large number for permute (3000), very small number for FreedmanLane(-3000):','Corrected P theshold:',...
        'Minimum overlap (1..numSubj):',...
        ['ROI (0=voxels ' sprintf('%s',kROInumbers) ' negative for correlations [multi OK]'],... 
        ['Modality (' sprintf('%s',kModalityNumbers) ') [multiple OK]'],...
        'Special (1=explicit voxel mask, 2=regress lesion volume, 3=de-skew, 4=include WM/CSF connectivity, 5=customROI, 6=TFCE, 7=reportROImeans, 8=SVM) [multi OK]'
        };
    dlg_title = ['Options for analyzing ' xlsname];
    num_lines = 1;
    if designUsesNiiImages
        def = {'0','0.05','1','UNUSED (design file specifies voxelwise images)','UNUSED (design file specifies voxelwise images)',''};
    else
        def = {'-1','0.01','2','0','1',''};
        %def = {'4000','0.05','2','4','6',''};
    end
    answer = inputdlg(prompt,dlg_title,num_lines,def);
    if isempty(answer), return; end;
    numPermute = str2double(answer{1});
    pThresh = str2double(answer{2});
    minOverlap = str2double(answer{3});
    if ~designUsesNiiImages
        roiIndices = str2num(answer{4}); %#ok<ST2NM> - we need to read vectors
        modalityIndices = str2num(answer{5}); %#ok<ST2NM> - we need to read vectors
    end
    special = str2num(answer{6}); %#ok<ST2NM> - we need to read vectors
    if any(special == 1) %select masking image
        [mfile,mpth] = uigetfile('*.nii;*.hdr','Select the mask image'); 
        if isequal(mfile,0), return; end;
        maskName=[mpth mfile];        
    end
    if any(special == 2) %adjust behavior for lesion volume
        regressBehav = true;
    end
    if any(special == 3) %adjust behavior for skew
        deSkew = true;
    end
    if any(special == 4) %allow WM/CSF connections
        GrayMatterConnectivityOnly = false;
    end
    if any(special == 5) %allow user to specify custom ROIs
        customROI = true;
        if (numel(roiIndices) ~= 1) || (roiIndices ~= 0)
            roiIndices = 0;
            fprintf('Custom ROIs require selecting the voxelwise modality\n');
        end
    end
    if any(special == 6) %allow WM/CSF connections
        doTFCE = true;
    end
    if any(special == 7) %report values for each ROI
        reportROIvalues = true;
    end
    if any(special == 8) %report values for each ROI
        doSVM = true;
    end
end;
if designUsesNiiImages %voxelwise images do not have regions of interest, and are only a single modality
    roiIndices = 0;
    modalityIndices = 1;
end
for i = 1: length(modalityIndices) %for each modality
    modalityIndex = modalityIndices(i);
    for j = 1: length(roiIndices)
        roiIndex = roiIndices(j);
        processExcelSub(designMat, roiIndex, modalityIndex,numPermute, pThresh, minOverlap, regressBehav, maskName, GrayMatterConnectivityOnly, deSkew, customROI, doTFCE, reportROIvalues, xlsname, kROIs, doSVM);
    end
end
%end nii_stat_mat()

function nii = isNII (filename)
%returns true if filename is .nii or .hdr file
[~, ~, ext] = fileparts(filename);
nii = (strcmpi('.hdr',ext) || strcmpi('.nii',ext));
%end isNII()

function [designMat, designUsesNiiImages] = readDesign (xlsname)
designUsesNiiImages = false;
[~,~,x] = fileparts(xlsname);
if strcmpi(x,'.tab') || strcmpi(x,'.txt')  || strcmpi(x,'.val')
    dMat = nii_tab2mat(xlsname);
else
    dMat = nii_xls2mat(xlsname , 'Data (2)','', true);
end
SNames = fieldnames(dMat);
numFields = length (SNames);
if numFields < 2
    error('File %s must have multiple columns (a column of file names plus a column for each behavior\n', xlsname);
end
numNII = 0; %number of NIfTI files
numMat = 0; %number of Mat files
numOK = 0;
%designMat = [];
for i=1:size(dMat,2)
    matname = deblank( dMat(i).(SNames{1}));
    isValid = false;
    if numel(SNames) > 1
        for j = 2:numel(SNames) 
            b = dMat(i).(SNames{j});
            if ~isempty(b) && isnumeric(b) && isfinite(b)
                isValid = true;
            end
        end
    end
    if ~isValid
        fprintf('Warning: no valid behavioral data for %s\n',matname);
        matname = '';
    end
    if ~isempty(matname)
        [matname] = findMatFileSub(matname,xlsname);
        [~, ~, ext] = fileparts(matname);
        if strcmpi('.mat',ext) || strcmpi('.hdr',ext) || strcmpi('.nii',ext)
            if strcmpi('.mat',ext)
                numMat = numMat + 1;
            elseif strcmpi('.hdr',ext) || strcmpi('.nii',ext)
                numNII = numNII + 1;
            end
            dMat(i).(SNames{1}) = matname;
            numOK = numOK + 1;
            designMat(numOK) = dMat(i); %#ok<AGROW>
        end
    end
end
if (numNII + numMat) == 0
    error('Unable to find any of the images listed in the file %s\n',xlsname);
end
if (numNII > 0) && (numMat >0) %mixed file
    error('Error: some images listed in %s are NIfTI format, others are Mat format. Use nii_nii2mat to convert NIfTI (.nii/.hdr) images.\n',xlsname);
end
if (numNII > 0)
    fprintf('Using NIfTI images. You will have more options if you use nii_nii2mat to convert NIfTI images to Mat format.\n');
    designUsesNiiImages = true;
end
%end readDesign()

function processExcelSub(designMat, roiIndex, modalityIndex,numPermute, pThresh, minOverlap, regressBehav, mask_filename, GrayMatterConnectivityOnly, deSkew, customROI, doTFCE, reportROIvalues, xlsname, kROIs, doSVM)
%GrayMatterConnectivityOnly = true; %if true, dti only analyzes gray matter connections
%kROIs = strvcat('bro','jhu','fox','tpm','aal','catani'); %#ok<*REMFF1>
%kModalities = strvcat('lesion','cbf','rest','i3mT1','i3mT2','fa','dti','md'); %#ok<REMFF1> %lesion, 2=CBF, 3=rest
[kModalities, ~] = nii_modality_list();
if (modalityIndex > size(kModalities,1)) || (modalityIndex < 1)
    fprintf('%s error: modalityIndex must be a value from 1..%d\n',mfilename,size(kModalities,1));
    return;
end
if roiIndex < 0
    kAnalyzeCorrelationNotMean = true;
    roiIndex = abs(roiIndex);
else
    kAnalyzeCorrelationNotMean = false;
end
if strcmpi('dtifc',deblank(kModalities(modalityIndex,:))) %read connectivity triangle
    kAnalyzeCorrelationNotMean = true;
end
if strcmpi('dti',deblank(kModalities(modalityIndex,:))) %read connectivity triangle
    kAnalyzeCorrelationNotMean = true;
end
if kAnalyzeCorrelationNotMean
   fprintf('analysis of connectivity between regions rather than mean intensity\n'); 
end
if roiIndex == 0 %voxelwise lesion analysis
   ROIfield = deblank(kModalities(modalityIndex,:));
else
    if doTFCE
        fprintf('doTFCE disabled: threshold free cluster enhancement for voxelwise analyses only\n');
        doTFCE = false;
    end
    if (roiIndex > size(kROIs,1)) || (roiIndex < 0)
        fprintf('%s error: for modality %d the roiIndex must be a value from 1..%d\n',mfilename,modalityIndex,size(kROIs,1));
        return;
    end
    [~,nam] = fileparts(deblank(kROIs(roiIndex,:)));
    ROIfield = [deblank(kModalities(modalityIndex,:)) '_' nam];
end
statname = [ROIfield '_' xlsname];%sprintf ('%s%s',deblank(kModalities(modalityIndex,:)),deblank(kROIs(roiIndex,:)));
SNames = fieldnames(designMat);
matnames = [];
for i=1:size(designMat,2)
    matnames = strvcat(matnames, deblank( designMat(i).(SNames{1})) ); %#ok<REMFF1>
end
designMat = rmfield(designMat,SNames{1}); %remove first column - mat name
% read in the image data
if roiIndex == 0
    subfield = '.dat';
elseif kAnalyzeCorrelationNotMean
    subfield = '.r';
else
    subfield = '.mean';
end
subfield = [ROIfield subfield];
%for large voxel datasets - first pass to find voxels that vary
voxMask = [];
%if false
if (~customROI) && (roiIndex == 0) && (size(matnames,1) > 10) && (doTFCE ~= 1) %voxelwise, large study
    fprintf('Generating voxel mask for large voxelwise statistics\n');
    idx = 0;
    for i = 1:size(matnames,1)
        [in_filename] = deblank(matnames(i,:));
        if isempty(in_filename)
            %warning already generated
        elseif isNII (in_filename)
            error('Please use nii_nii2mat before conducting a large voxelwise statistics');
        elseif (exist (in_filename, 'file'))
            dat = load (in_filename);
            if  issubfieldSub(dat,subfield)
                img = dat.(ROIfield).dat;
                %store behavioral and relevant imaging data for ALL relevant valid individuals
                idx = idx + 1;
                if idx == 1
                    voxMask = zeros(size(img));
                    
                end
                img(~isfinite(img)) = 0;
                img(img ~= 0) = 1;
                voxMask  = voxMask + img;
                
            else
                fprintf('Warning: File %s does not have data for %s\n',in_filename,subfield);
            end

        end
    end %for each individual
    voxMask(voxMask < minOverlap) = 0;
    voxMask(voxMask > 0) = 1;
    %voxMask = voxMask(:); %make 1d
    nOK = sum(voxMask(:) > 0);
    fprintf('%d of %d voxels (%g%%) show signal in at least %d participants\n',nOK, numel(voxMask),100*nOK/numel(voxMask), minOverlap );
    if nOK < 1
        error('No voxels survive in mask');
    end
end
idx = 0;
for i = 1:size(matnames,1)
    [in_filename] = deblank(matnames(i,:));
    if isempty(in_filename)
        %warning already generated
    elseif (exist (in_filename, 'file'))
        if isNII (in_filename)
            idx = idx + 1; 
            data = [];
            data.lesion.hdr = spm_vol (in_filename);
            data.lesion.dat = spm_read_vols (data.lesion.hdr);
        	data.filename = in_filename;
            data.behav = designMat(i); % <- crucial: we inject behavioral data from Excel file!
            subj_data{idx} = data; %#ok<AGROW>         
        else
            dat = load (in_filename);
            %if  issubfieldSub(dat,'lesion.dat') 
            %	fprintf ('Volume %g for %s\n',sum(dat.lesion.dat(:)), in_filename);
            %end
            %if  isfield(dat,subfield) % && ~isempty (data.behav)
            if (roiIndex > 0) && (~kAnalyzeCorrelationNotMean) && ~issubfieldSub(dat,subfield)
                voxField = [deblank(kModalities(modalityIndex,:)) '.dat'];
                if  issubfieldSub(dat,voxField) %we can generate ROI data from voxel data
                    fprintf('Creating %s for %s\n',subfield,in_filename);
                    %dat.(deblank(kModalities(modalityIndex,:))).hdr
                    roiName = deblank(kROIs(roiIndex,:)) ;
                    sn=[deblank(kModalities(modalityIndex,:)) '_'];
                    nii_roi2stats (roiName, dat.(deblank(kModalities(modalityIndex,:))).hdr, dat.(deblank(kModalities(modalityIndex,:))).dat, sn,in_filename);
                    dat = load (in_filename);    
                end
            end   
            if  issubfieldSub(dat,subfield)
                %store behavioral and relevant imaging data for ALL relevant valid individuals
                idx = idx + 1;
                subj_data{idx}.filename = in_filename; %#ok<AGROW>
                subj_data{idx}.behav = designMat(i); %#ok<AGROW>
                
                if isempty(voxMask)
                    subj_data{idx}.(ROIfield)  = dat.(ROIfield); %#ok<AGROW>
                else
                    %dat = dat.(ROIfield).dat(voxMask == 1);
                    %subj_data{i}.(ROIfield).dat = dat;%#ok<AGROW>
                    subj_data{i}.(ROIfield).hdr = dat.(ROIfield).hdr;
                    subj_data{i}.(ROIfield).dat = dat.(ROIfield).dat(voxMask == 1);
                end
                    
                if regressBehav && isfield (dat.lesion, 'dat')
                    dat.lesion.dat(isnan(dat.lesion.dat(:)))=0; %zero NaNs: out of brain
                    subj_data{idx}.lesion.vol = sum(dat.lesion.dat(:)); %#ok<AGROW>
                end
                if (idx == 1) && (roiIndex < 1) %first image of voxelwise analyses 
                    vox = numel(subj_data{i}.(ROIfield).dat(:));
                    vox = vox * size(matnames,1); %worst case scenario: all individuals have image data
                    gb = (vox * 8)/ (1024^3); %doubles use 8-bytes
                    fprintf('The imaging data will require %.3f gb of memory\n',gb);
                end
            else
                fprintf('Warning: File %s does not have data for %s\n',in_filename,subfield);
            end 
        end
    else
        fprintf('Unable to find file %s\n', in_filename);
    end
end
clear('dat'); %these files tend to be large, so lets explicitly free memory
n_subj = idx;
if n_subj < 3
    fprintf('Insufficient data for statistics: only found files %d with both "behav" and "%s" fields\n',n_subj,ROIfield);
    return;
end
% get the list of numeric fields of behavioural data
fields = fieldnames (subj_data{1}.behav); %fields = fieldnames (data.behav);
idx = 1;
for i = 1:length (fields)
    for s = 1:n_subj
        if isnumeric (subj_data{s}.behav.(fields{i}))
            beh_names{idx} = fields{i};  %#ok<AGROW>
            idx = idx + 1;
            break
        end
    end
end
n_beh = idx - 1;
if ~exist('beh_names','var')
    fprintf('No valid behavioral variables found\n');
    return
end
%beh_names = [];beh_names{1} = 'ASRS_total';n_beh = 1;fprintf('WARNING: Beta release (single behavior)#@\n');%#@
% make sure all the subjects have all numeric fields
beh = zeros(n_subj,n_beh);
beh(:) = nan;
for i = 1:n_subj
    for j = 1:n_beh %length(beh_names)
        if isfield (subj_data{i}.behav, beh_names{j})
            if ~isnumeric(subj_data{i}.behav.(beh_names{j}) )
                fprintf ('Warning! Subject %s reports non-numeric data for field %s\n',subj_data{i}.filename, beh_names{j} );
            elseif strcmpi(subj_data{i}.behav.(beh_names{j}),'NaN') || (isnan(subj_data{i}.behav.(beh_names{j}) ))
                fprintf ('Warning! Subject %s reports NaN for field %s\n',subj_data{i}.filename, beh_names{j} );  
            else
                beh(i, j) = subj_data{i}.behav.(beh_names{j});
                %fprintf('%d %d %f\n',i,j, beh(i, j));
                %class(beh(i, j))
            end
        else
            disp (['Warning! Subject ' subj_data{i}.filename ' does not have a field ' beh_names{j}]);
        end
    end   
end
if regressBehav
    vol = zeros(n_subj,1);
    vol(:) = nan;
    for i = 1:n_subj
        %subj_data{idx}.lesion.vol
        if isfield (subj_data{i}.lesion, 'vol')
            vol(i) = subj_data{i}.lesion.vol;
            fprintf ('Participant\t%s\tVolume\t%g\n',subj_data{i}.filename,vol(i));
        else
            fprintf ('Problem regressing for lesion volume! Subject %s does not have the field ".lesion.dat"\n', subj_data{i}.filename);
        end;  
    end;
    if sum(~isnan(vol(:))) > 1 
        for i = 1:n_beh
            %beh_names1 = deblank(beh_names(i));
            beh1 = beh(:,i);
            good_idx = intersect (find(~isnan(beh1)), find(~isnan(vol)));
            dat = beh1(good_idx)'; %behavior is the data
            reg = vol(good_idx)'; %lesion volume is our regressor            
            preSD = std(dat);
            if ~isnan(std(dat)) && (preSD ~= 0) && (std(reg) ~= 0) %both data and regressor have some variability            
                G = ones (2, size(dat,2)); %constant
                G (2, :) = reg; % linear trend
                G_pseudoinv = G' / (G * G'); %aka: G_pseudoinv = G' * inv (G * G');
                Beta = dat * G_pseudoinv;
                dat = dat - Beta*G; %mean is zero
                fprintf('Regressing %s with lesion volume reduces standard deviation from %f to %f\n',char(deblank(beh_names(i))),preSD, std(dat) );
                beh(good_idx,i) = dat;
            end
        end
    end
end %if regressBehav - regress behavioral data using lesion volume
roiName = '';
if roiIndex == 0 %voxelwise lesion analysis
    les_names = '';
    hdr = subj_data{1}.(ROIfield).hdr;
    for i = 1:n_subj
        if (i > 1) && (numel(subj_data{i}.(ROIfield).dat(:)) ~= numel(subj_data{1}.(ROIfield).dat(:)))
            %error('Number of voxels varies between images. Please reslice all images to the same dimensions');
            Interp = ~isBinSub(subj_data{i}.(ROIfield).dat); %interpolate continuous images, do not interpolate binary images
            fprintf('warning: reslicing %s to match dimensions of other images. Interpolation = %d\n',subj_data{i}.filename, Interp);
            [~, outimg] = nii_reslice_target(subj_data{i}.(ROIfield).hdr, subj_data{i}.(ROIfield).dat(:), subj_data{1}.(ROIfield).hdr, Interp) ;
            subj_data{i}.(ROIfield).dat = outimg; %#ok<AGROW>
            %fprintf('%d, %d\n',subj_data{i}.filename);
            
        end    
        %fprintf('%d/%d= %d\n',i,n_subj, numel(subj_data{i}.(ROIfield).dat(:)));
        
        les(i, :) = subj_data{i}.(ROIfield).dat(:); %#ok<AGROW>
    end    
    nanIndex = isnan(les(:));
    if sum(nanIndex(:)) > 0
        les(nanIndex) = 0;
        fprintf('Warning: Not a number values in images replaced with zeros\n');
    end
    if  exist('mask_filename','var') && ~isempty(mask_filename) %apply explicit masking image
            mask_hdr = spm_vol (mask_filename);
            mask_img = spm_read_vols (mask_hdr);
            mask_img(isnan(mask_img)) = 0; %exclude voxels that are not a number
            if ~isequal(mask_hdr.mat, hdr.mat) || ~isequal(mask_hdr.dim(1:3), hdr.dim(1:3))
                fprintf('Warning: mask dimensions differ from data: attempting to reslice (blurring may occur)\n');
                inimg = mask_img; %reshape(mask_img,mask_hdr.dim(1:3)); %turn 1D vector into 3D
                imgdim = hdr.dim(1:3);
                mask_img = zeros(imgdim);
                for i = 1:imgdim(3)
                    M = inv(spm_matrix([0 0 -i])*inv(hdr.mat)*mask_hdr.mat); %#ok<MINV>
                    mask_img(:,:,i) = spm_slice_vol(inimg, M, imgdim(1:2), 1); % 1=linear interp; 0=nearest neighbor            
                end %for each slice
            end %if dimensions differ
            mask_img = mask_img(:); %create a 1D vector
            fprintf('Including the %d voxels (of %d possible) in mask %s\n', nnz(mask_img), numel(mask_img), mask_filename);
            for i = 1:n_subj
                les(i, mask_img == 0) = 0;       %#ok<AGROW>
            end  %mask each subject's data
    end %if mask
else %if voxelwise else region of interest analysis
    %find the appropriate ROI
    %[mpth,~,~] = fileparts( deblank (which(mfilename)));
    %roiName = fullfile(mpth,[deblank(kROIs(roiIndex,:)) '1mm.nii']);
    roiName = [deblank(kROIs(roiIndex,:)) '.nii'];
    if ~exist(roiName,'file')
        fprintf('No images created (unable to find image named %s\n',roiName);
        return;
    end
    hdr = spm_vol(roiName);
    %provide labels for each region
    les_names = cellstr(subj_data{1}.(ROIfield).label); %les_names = cellstr(data.(ROIfield).label);
    %next: create labels for each region, add image values
    if kAnalyzeCorrelationNotMean %strcmpi('dti',deblank(kModalities(modalityIndex,:))) %read connectivity triangle
        labels = les_names;
        for i = 1:n_subj
            %http://stackoverflow.com/questions/13345280/changing-representations-upper-triangular-matrix-and-compact-vector-octave-m
            %extract upper triangle as vector
            A = subj_data{i}.(ROIfield).r;
            if GrayMatterConnectivityOnly == true
                [les_names,A] = shrink_matxSub(labels,A);
                %fprintf('Only analyzing gray matter regions (%d of %d)\n',size(les_names,1),size(labels,1) );
            end
            B = triu(ones(size(A)),1);
            les(i, :) = A(B==1); %#ok<AGROW>
            % A=[0 1 2 4; 0 0 3 5; 0 0 0 6; 0 0 0 0];  B = triu(ones(size(A)),1); v =A(B==1); v = 1,2,3,4,5,6
        end
        if GrayMatterConnectivityOnly
                fprintf('Connectivity only analyzing gray matter regions (%d of %d)\n',size(les_names,1),size(labels,1) );
        end
    else %not DTI n*n connectivity matrix
        for i = 1:n_subj
            les(i, :) = subj_data{i}.(ROIfield).mean;     %#ok<AGROW>
        end
    end
end %if voxelwise else roi
if customROI
    if roiIndex ~= 0, fprintf('Custom ROIs require selecting the voxelwise modality\n'); end;
    roiNames = spm_select(inf,'image','Select regions of interest');
    lesVox = les;
    les = zeros(n_subj, size(roiNames,1) );
    for i = 1:n_subj
        [les(i, :), les_names] = nii_nii2roi(roiNames,hdr,lesVox(i, :)); 
    end
    hdr = []; %no image for these regions of interest
    les_names = cellstr(les_names);
end %if custom ROI
if (numPermute < -2) && (numPermute >= -500)
    fprintf('Error: Current software can not understand %d permutations (reserved for future usage).\n', numPermute);
    return;
end
if ((size(beh,2) <= 1) || sum(isnan(beh(:)))) > 0 && (numPermute < -500)
    fprintf('Error: Freedman-Lane requires at least two columns of behavioral data and no empty cells.\n');
    return;
end
if deSkew
    for i =1:n_beh
        if isBinomialSub(beh(:,i))
            fprintf('Behavior %s is binomial\n',beh_names{i});
        else %if binomial else continuous
            sk = zskewSub(beh(:,i));
            %transform skewed data http://fmwww.bc.edu/repec/bocode/t/transint.html
            if abs(sk) < 1.96
                fprintf('Behavior %s has a Z-skew of %f\n',beh_names{i}, sk);
            else %if not skewed else transfrom
                mn = min(beh(:,i)); 
                beh(:,i) = beh(:,i) - mn; %24Sept2014 - previously would crash with negative values, e.g. sqrt(-3) fails isreal
                if sk > 1.96
                    beh(:,i) = sqrt(beh(:,i));
                else %negative skew
                    beh(:,i) = beh(:,i).^2;
                end
                skT = zskewSub(beh(:,i));
                fprintf('Behavior %s had a Z-skew of %f, after transform this became %f\n',beh_names{i}, sk, skT);
            end %if not significantly skewed else transform  
        end %if binomial else continuous
    end %for each behavior
end %if de-Skew
if doTFCE 
    hdrTFCE = hdr.dim;
else
    hdrTFCE = [];
end
if (reportROIvalues) && (numel(les_names) < 1)
    fprintf('Unable to create a ROI report [voxelwise analyses]\n');
elseif (reportROIvalues) && (kAnalyzeCorrelationNotMean)
    fprintf('Unable to create a ROI report [correlation matrix analyses]\n');
elseif reportROIvalues
    %first row: column labels
    fprintf('filename\t');
    for j = 1:numel(les_names)
         fprintf('%s\t', les_names{j}); 
    end
    for j = 1:n_beh %length(beh_names)
        fprintf('%s\t', beh_names{j});
    end
    fprintf('\n');
    for i = 1:n_subj
        fprintf('%s\t',subj_data{i}.filename);
        for j = 1:numel(les_names)
             fprintf('%g\t',les(i, j));
        end
        for j = 1:n_beh %length(beh_names)
           if isnan(beh(i, j))
            fprintf('\t');               
           else
            fprintf('%g\t',beh(i, j));
           end
        end 
        fprintf('\n');
    end
end

if sum(isnan(beh(:))) > 0
    for i =1:n_beh
        fprintf('Behavior %d/%d: estimating behaviors one as a time (removing empty cells will lead to faster analyses)\n',i,n_beh);
        beh_names1 = deblank(beh_names(i));
        beh1 = beh(:,i);
        good_idx = find(~isnan(beh1));
        beh1 = beh1(good_idx);
        les1 = zeros(length(good_idx),size(les,2));
        for j = 1:length(good_idx)
            les1(j, :) = les(good_idx(j), :) ;    
            %les1(j,1) = beh1(j); %to test analyses
        end 
        if doSVM
            nii_stat_svm(les1, beh1, beh_names1,statname, les_names, subj_data, roiName);
        else
            nii_stat_core(les1, beh1, beh_names1,hdr, pThresh, numPermute, minOverlap,statname, les_names,hdrTFCE, voxMask);
        end
        %fprintf('WARNING: Beta release (quitting early, after first behavioral variable)#@\n');return;%#@
    end
else
    %for aalcat we may want to remove one hemisphere
    %les_names(:,1:2:end)=[]; % Remove odd COLUMNS: left in AALCAT: analyze right
    %les(1:2:end)=[]; % Remove odd COLUMNS: left in AALCAT: analyze right
    %les_names(2:2:end)=[]; % Remove even COLUMNS: right in AALCAT: analyze left
    %les(:,2:2:end)=[]; % Remove even COLUMNS: right in AALCAT: analyze left
    if doSVM    
        nii_stat_svm(les, beh, beh_names, statname, les_names, subj_data, roiName);
    else
        nii_stat_core(les, beh, beh_names,hdr, pThresh, numPermute, minOverlap,statname, les_names, hdrTFCE, voxMask);
    end
end
%end processMatSub()

function [smalllabels, smallmat] = shrink_matxSub(labels, mat)
%removes columns/rows where label does not end with text '|1'
%  useful as the labels end with |1, |2, |3 for gray matter, white matter and CSF
% l = strvcat('ab|1', 'abbs|2','c|1')
% m = [1 2 3; 4 5 6; 7 8 9];
% [sl,sm] = shrink_matxSub(l,m);
% s now = [1 3; 7 9] - removes columsn and row without |1
index = strfind(cellstr(labels),'|1');
index = ~cellfun('isempty',index);
if (sum(index(:)) == 0)
    smallmat = mat;
    smalllabels = labels;
    fprintf(' Analysis will include all regions (this template does not specify white and gray regions)')
    return
end;
smallmat = mat(index,:);
smallmat = smallmat(:,index);
smalllabels = labels(index,:);
%end shrink_matxSub()

function [fname] = findMatFileSub(fname, xlsname)
%looks for a .mat file that has the root 'fname', which might be in same
%folder as Excel file xlsname
fnameIn = fname;
[pth,nam,ext] = fileparts(fname);
if strcmpi('.nii',ext) || strcmpi('.hdr',ext) || strcmpi('.img',ext)%look for MAT file
    ext = '.mat';
    %fprintf('Excel file %s lists %s, but files should be in .mat format\n',xlsname,fnameIn);
else
    if exist(fname, 'file'), return; end;
end
fname = fullfile(pth,[nam '.mat']);
if exist(fname, 'file'), return; end;
%next - check folder of Excel file
[xpth,~,~] = fileparts(xlsname);   
fname = fullfile(xpth,[nam ext]);
if exist(fname, 'file'), return; end;
fname = fullfile(xpth,[nam '.mat']);
if exist(fname, 'file'), return; end;
%next check for nii file:
fname = findNiiFileSub(fnameIn, xlsname);
if exist(fname, 'file'), return; end;
fprintf('Unable to find image %s listed in %s: this should refer to a .mat (or .nii) file. (put images in same folder as design file)\n',fnameIn, xlsname);
fname = '';
%end findMatFileSub()

function [fname] = findNiiFileSub(fname, dir)
[pth,nam,~] = fileparts(fname);
fname = fullfile(pth,[nam '.nii']);
if exist(fname, 'file'), return; end;
fname = fullfile(pth,[nam '.hdr']);
if exist(fname, 'file'), return; end;
if exist(dir,'file') == 7
    pth = dir;
else
    [pth,~,~] = fileparts(dir);
end
fname = fullfile(pth,[nam '.nii']);
if exist(fname, 'file'), return; end;
fname = fullfile(pth,[nam '.hdr']);
if exist(fname, 'file'), return; end;
%findNiiFileSub

function b = isBinomialSub(i)
%returns true if vector is binomial (less than three distinct values)
nMin = sum(i(:)==min(i(:)));
nMax = sum(i(:)==max(i(:)));
if (nMin+nMax) ~= length(i(:))
    b = false;
else
    b = true;
end
%end isBinomialSub()

function s = zskewSub(i)
%http://office.microsoft.com/en-us/excel-help/skew-HP005209261.aspx
%zSkew dividing the Skew by the Standard Error of the Skew
%standard error of Skewness http://en.wikipedia.org/wiki/Talk%3ASkewness, 
%http://www.unesco.org/webworld/idams/advguide/Chapt3_1_3.htm 
%http://jalt.org/test/PDF/Brown1.pdf -> Tabachnick and Fidell, 1996
n = numel(i);
mn = mean(i);
s = std(i);
if (n < 3) || (s == 0) 
    s = 0;
    return
end
s = sum(((i-mn)/s).^3);
s = n/((n-1)*(n-2)) * s;
s = s/(sqrt(6/n)); %convert skew to Z-skew 
%end zskewSub()

function [r] = issubfieldSub(s, f)
%https://fieldtrip.googlecode.com/svn/trunk/utilities/issubfield.m
try
  getsubfieldSub(s, f);    % if this works, then the subfield must be present  
  r = true;
catch %#ok<CTCH>
  r = false;                % apparently the subfield is not present
end
%end issubfieldSub()

function [s] = getsubfieldSub(s, f)
% GETSUBFIELD returns a field from a structure just like the standard
% Matlab GETFIELD function, except that you can also specify nested fields
% using a '.' in the fieldname. The nesting can be arbitrary deep.
%
% Use as
%   f = getsubfield(s, 'fieldname')
% or as
%   f = getsubfield(s, 'fieldname.subfieldname')
%
% See also GETFIELD, ISSUBFIELD, SETSUBFIELD
% Copyright (C) 2005, Robert Oostenveld
%
% This file is part of FieldTrip, see http://www.ru.nl/neuroimaging/fieldtrip
% for the documentation and details.
%
%    FieldTrip is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    FieldTrip is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with FieldTrip. If not, see <http://www.gnu.org/licenses/>.
%
% $Id: getsubfield.m 7123 2012-12-06 21:21:38Z roboos $
if iscell(f)
  f = f{1};
end
if ~ischar(f)
  error('incorrect input argument for fieldname');
end
t = {};
while (1)
  [t{end+1}, f] = strtok(f, '.'); %#ok<AGROW,STTOK>
  if isempty(f)
    break
  end
end
s = getfield(s, t{:});
%end getsubfieldSub()

function isBin = isBinSub(x)
nMin = sum(x(:)==min(x(:)));
nMax = sum(x(:)==max(x(:)));
%isBin = ((nMax + nMin) == numel(x));
isBin = ((nMax + nMin + sum(isnan(x(:)))) == numel(x));
%end isBinSub