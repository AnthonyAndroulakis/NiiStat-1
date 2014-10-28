function [labels, predicted_labels,z_map] = nii_stat_svr_core (xlsname, normRowCol, verbose, minUnique)
% xlsname : file name to analyze
% normRowCol : normalize none [0, default], rows [1], or columns [2]
%example
% nii_stat_svr_core ('lesionacute_better_svr.tab')

if ~exist('xlsname','var') %if Excel file not specified, have user select one
   [file,pth] = uigetfile({'*.xls;*.xlsx;*.txt;*.tab','Excel/Text file';'*.txt;*.tab','Tab-delimited text (*.tab, *.txt)'},'Select the design file'); 
   if isequal(file,0), return; end;
   xlsname=[pth file];
end
if ~exist('normRowCol','var')
    normRowCol = 0; %[0, default], rows [1], or columns [2]
end
if ~exist('verbose','var')
    verbose = false;
end
if ~exist('minUnique','var')
   minUnique = 0; 
end
svmdir = [fileparts(which(mfilename))  filesep 'libsvm' filesep];
if ~exist(svmdir,'file') 
    error('Unable to find utility scripts folder %s',svmdir);
end
addpath(svmdir); %make sure we can find the utility scripts
%addpath c:/code/libsvm-3.11/matlab;
[~,~,x] = fileparts(xlsname);
if strcmpi(x,'.tab') || strcmpi(x,'.txt')  || strcmpi(x,'.val')
    num = tabreadSub (xlsname);
    
else
    [num, ~, ~] = xlsread (xlsname);
    num(:,1) = []; % remove first column (subject name)
end
n_subj = size (num, 1);
n_dim = size (num, 2) - 1; %final column is predictor
data = num (:, 1:n_dim);
if minUnique > 1 %
    %remove columns with fewer than N number of different values
    [data , good_idx] = columnUniqueThreshSub(data, minUnique);
else
    %else remove columns with NO variability
    [data, good_idx] = requireVarSub(data);
end
if normRowCol ==  -2% rows [1], or columns [2], minus means exclude final column
    fprintf('Normalizing so each column has range 0..1 (last column excluded)\n');
    data(:,1:end-1) = normColSub(data(:,1:end-1));
elseif normRowCol ==  -1% rows [1], or columns [2], minus means exclude final column
    fprintf('Normalizing so each row has range 0..1 (last column excluded)\n');
    data(:,1:end-1) = normRowSub(data(:,1:end-1));
elseif normRowCol ==  1% rows [1], or columns [2]
    fprintf('Normalizing so each row has range 0..1\n');
    data = normRowSub(data);
elseif normRowCol ==  2% rows [1], or columns [2]
    fprintf('Normalizing so each column has range 0..1\n');
    data = normColSub(data);
end
labels = num (:, size (num, 2));
predicted_labels = zeros(n_subj,1); %pre-allocate memory
map = zeros(size(data)); %pre-allocate memory

for subj = 1:n_subj
    train_idx = setdiff (1:n_subj, subj);
    train_data = data (train_idx, :);
    train_labels = labels (train_idx);
    %SVM = svmtrain (train_labels, train_data, '-s 3');
    %predicted_labels(subj) = svmpredict (labels(subj), data(subj, :), SVM);
    if verbose
        SVM = svmtrain (train_labels, train_data, '-s 3');
        predicted_labels(subj) = svmpredict (labels(subj), data(subj, :), SVM);
    else %if verbose else silent
        [~, SVM] = evalc ('svmtrain (train_labels, train_data, ''-s 3'')');
        [~, predicted_labels(subj), ~, ~] = evalc ('svmpredict (labels(subj), data(subj, :), SVM)');
    end %if verbose else silent
    map (subj, :) = SVM.sv_coef' * SVM.SVs;
end
%accuracy = sum (predicted_labels' == labels) / n_subj;
%[r, p] = corr (predicted_labels', labels)
[r, p] = corrcoef (predicted_labels', labels);
fprintf('r=%g p=%g numObservations=%d numPredictors=%d\n',r(1,2),p(1,2),size (data, 1),size (data, 2));
mean_map = mean (map, 1);
z_map = mean_map ./ std (mean_map);
if exist('good_idx','var') %insert NaN for unused features
    z_mapOK = zeros(n_dim,1);
    z_mapOK(:) = nan;
    z_mapOK(good_idx) = z_map;
    z_map = z_mapOK;
end
plot (labels, predicted_labels, 'o');
axis ([min(labels(:)) max(labels(:)) min(labels(:)) max(labels(:))]);
%set (gca, 'XTick', [0 1 2 3 4]);
xlabel ('Actual score');
ylabel ('Predicted score');

function num = tabreadSub(tabname)
%read cells from tab based array. 
fid = fopen(tabname);
num = [];
row = 0;
while(1) 
	datline = fgetl(fid); % Get second row (first row of data)
	%if (length(datline)==1), break; end
    if(datline==-1), break; end %end of file
    if datline(1)=='#', continue; end; %skip lines that begin with # (comments)
    tabLocs= strfind(datline,char(9)); %findstr(char(9),datline); % find the tabs
    row = row + 1;
    if (row < 2) , continue; end; %skip first row 
    if (tabLocs < 1), continue; end; %skip first column
    dat=textscan(datline,'%s',(length(tabLocs)+1),'delimiter','\t');
    for col = 2: size(dat{1},1) %excel does not put tabs for empty cells (tabN+1)
    	num(row-1, col-1) = str2double(dat{1}{col}); %#ok<AGROW>
    end
end %while: for whole file
fclose(fid);
%end tabreadSub()

function [good_dat, good_idx] = requireVarSub (dat)
good_idx=[];
for col = 1:size(dat,2)
    if sum(isnan(dat(:,col))) > 0
       %fprintf('rejecting column %d (non-numeric data')\n',col) %
    elseif min(dat(:,col)) ~= max(dat(:,col))
        good_idx = [good_idx, col];  %#ok<AGROW>
    end
end %for col: each column
if sum(isnan(dat(:))) > 0
    fprintf('Some predictors have non-numeric values (e.g. not-a-number)\n');
end
if numel(good_idx) ~= size(dat,2)
    fprintf('Some predictors have no variability (analyzing %d of %d predictors)\n',numel(good_idx), size(dat,2));
end
good_dat = dat(:,good_idx);
%end requireVarSub()

function x = normColSub(x)
%normalize each column for range 0..1
% x = [1 4 3 0; 2 6 2 5; 3 10 2 2] -> x = [0 0 1 0; 0.5 0.333 0 1; 1 1 0 0.4]
if size(x,1) < 2 %must have at least 2 rows
    fprintf('Error: normalizing columns requires multiple rows\n');
    return
end
x = bsxfun(@minus,x,min(x,[],1)); %translate so minimum = 0
x = bsxfun(@rdivide,x,max(x,[],1)); %scale so range is 1
%end normColSub()

function x = normRowSub(x)
%normalize each column for range 0..1
% x = [1 4 3 0; 2 6 2 5; 3 10 2 2] -> x = [0.25 1 0.75 0; 0 1 0 0.75; 0.125 1 0 0]
if size(x,2) < 2 %must have at least 2 rows
    fprintf('Error: normalizing rows requires multiple columns');
    return
end
if min(max(x,[],2)-min(x,[],2)) == 0
    fprintf('Error: unable to normalize rows: some have no variability');
    return;
end
x = bsxfun(@minus,x,min(x,[],2)); %translate so minimum = 0
x = bsxfun(@rdivide,x,max(x,[],2)); %scale so range is 1
%end normRowSub()

% function x = columnUniqueThreshSub(x, minUnique)
% %removes columns that have fewer than minUnique different values
% n_col = size(x,2);
% for c = n_col:-1:1
%     if numel(unique(x(:,c))) < minUnique
%         x(:,c) = [];
%     end
% end
% if n_col ~= size(x,2)
%     fprintf('%d columns of %d had at least %d unique values\n',size(x,2), n_col, minUnique);
% end
%end columnUniqueThreshSub()

function [good_dat, good_idx] = columnUniqueThreshSub(dat, minUnique)
n_col = size(dat,2);
good_idx=[];
for col = 1:n_col    
    %how many items have the most frequent value
    s = sum(dat(:,col) == mode(dat(:,col)));
    if (size(dat,1) - s) >= minUnique
        good_idx = [good_idx, col];  %#ok<AGROW>
    end
end
if numel(good_idx) ~= size(dat,2)
     fprintf('%d columns of %d had at least %d items in the smaller class\n',numel(good_idx), n_col, minUnique);
end
good_dat = dat(:,good_idx);
%end columnUniqueThreshSub()

% function x = columnUniqueThreshSubOld(x, minUnique)
% %removes columns that have fewer than minUnique different values
% % x = [ 1 2 3 3 5 6; 2 2 2 2 3 3]'; ->minUnique(3) -> [1 2 3 3 5 6]'
% n_col = size(x,2);
% for c = size(x,2):-1:1    
%     %how many items have the most frequent value
%     s = sum(x(:,c) == mode(x(:,c)));
%     if (size(x,1) - s) < minUnique
%         x(:,c) = [];
%     end
% end
% if n_col ~= size(x,2)
%      fprintf('%d columns of %d had at least %d items in the smaller class\n',size(x,2), n_col, minUnique);
% end
% %end columnUniqueThreshSub()