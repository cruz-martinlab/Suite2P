function [ops, U, Sv, V, Fs, sdmov, mov] = get_svdForROI(ops, clustModel)

% iplane = ops.iplane;
U = []; Sv = []; V = []; Fs = []; sdmov = [];
[Ly, Lx] = size(ops.mimg1);

ntotframes          = ceil(sum(ops.Nframes));
ops.NavgFramesSVD   = min(ops.NavgFramesSVD, ntotframes);
nt0 = ceil(ntotframes / ops.NavgFramesSVD);


ops.NavgFramesSVD = floor(ntotframes/nt0);
nimgbatch = nt0 * floor(2000/nt0);

ix = 0;
fid = fopen(ops.RegFile, 'r');

mov = zeros(numel(ops.yrange), numel(ops.xrange), ops.NavgFramesSVD, 'single');

while 1
    data = fread(fid,  Ly*Lx*nimgbatch, '*int16');
    if isempty(data)
        break;
    end
    data = single(data);
    data = reshape(data, Ly, Lx, []);
    
    %     data = data(:,:,1:30:end);
    % subtract off the mean of this batch
    
    if nargin==1
        data = bsxfun(@minus, data, mean(data,3));
    end
    %     data = bsxfun(@minus, data, ops.mimg1);
    
    nSlices = nt0*floor(size(data,3)/nt0);
    if nSlices~=size(data,3)
        data = data(:,:, 1:nSlices);
    end
    
    data = reshape(data, Ly, Lx, nt0, []);
    davg = squeeze(mean(data,3));
    
    mov(:,:,ix + (1:size(davg,3))) = davg(ops.yrange, ops.xrange, :);
    
    ix = ix + size(davg,3);
end
fclose(fid);

mov = mov(:, :, 1:ix);

if nargin>1 && strcmp(clustModel, 'CNMF')
    mov = mov - min(mov(:)); 
end
% mov = mov - repmat(mean(mov,3), 1, 1, size(mov,3));
%% SVD options

if nargin==1
    ops.nSVDforROI = min(ops.nSVDforROI, size(mov,3));
    
    if ops.sig>0.05
        for i = 1:size(mov,3)
            I = mov(:,:,i);
            I = my_conv2(I, ops.sig, [1 2]); %my_conv(my_conv(I',ops.sig)', ops.sig);
            mov(:,:,i) = I;
        end
    end
    
    mov             = reshape(mov, [], size(mov,3));
    sdmov           = mean(mov.^2,2).^.5;
    % mov             = mov./repmat(sdmov, 1, size(mov,2));
    mov             = bsxfun(@rdivide, mov, sdmov);
    if ops.useGPU
        COV             = gpuBlockXtX(mov)/size(mov,1);
    else
        COV             = mov' * mov/size(mov,1);
    end
    
    ops.nSVDforROI = min(size(COV,1)-2, ops.nSVDforROI);
    
    if ops.useGPU && size(COV,1)<1.2e4
        [V, Sv, ~]      = svd(gpuArray(double(COV)));
        V               = single(V(:, 1:ops.nSVDforROI));
        Sv              = single(diag(Sv));
        Sv              = Sv(1:ops.nSVDforROI);
        %
        Sv = gather(Sv);
        V = gather(V);
    else
        [V, Sv]          = eigs(double(COV), ops.nSVDforROI);
        Sv              = single(diag(Sv));
    end
    
    if ops.useGPU
        U               = normc(gpuBlockXY(mov, V));
    else
        U               = normc(mov * V);
    end
    U               = single(U);
    
    %
    fid = fopen(ops.RegFile, 'r');
    
    ix = 0;
    Fs = zeros(ops.nSVDforROI, sum(ops.Nframes), 'single');
    while 1
        data = fread(fid,  Ly*Lx*nimgbatch, '*int16');
        if isempty(data)
            break;
        end
        data = single(data);
        data = reshape(data, Ly, Lx, []);
        
        % subtract off the mean of this batch
        data = bsxfun(@minus, data, mean(data,3));
        %     data = bsxfun(@minus, data, ops.mimg1);
        data = data(ops.yrange, ops.xrange, :);
        if ops.useGPU
            Fs(:, ix + (1:size(data,3))) = gpuBlockXtY(U, reshape(data, [], size(data,3)));
        else
            Fs(:, ix + (1:size(data,3))) = U' * reshape(data, [], size(data,3));
        end
        
        ix = ix + size(data,3);
    end
    fclose(fid);
    
    %
    U = reshape(U, numel(ops.yrange), numel(ops.xrange), []);
    if ~exist(ops.ResultsSavePath, 'dir')
        mkdir(ops.ResultsSavePath);
    end
    if getOr(ops, {'writeSVDroi'}, 0)
        try
            save(sprintf('%s/SVDroi_%s_%s_plane%d.mat', ops.ResultsSavePath, ...
                ops.mouse_name, ops.date, ops.iplane), 'U', 'Sv', 'V', 'ops', '-v6');
        catch
            save(sprintf('%s/SVDroi_%s_%s_plane%d.mat', ops.ResultsSavePath, ...
                ops.mouse_name, ops.date, ops.iplane), 'U', 'Sv', 'V', 'ops');
        end
    end
end