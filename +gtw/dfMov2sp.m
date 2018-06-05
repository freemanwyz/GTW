function [df0ip,dfm,intMap,spSz,spLst] = dfMov2sp(df0,m0,vMap0,seSel,riseOnly,varEst)
% dfMov2sp convert df movie to super pixels emphasizing bright parts
% df0 may contain missing values

[H0,W0,T0] = size(df0);

% ----------------------------------------------------------------
% imputation voxels in other super events
m0Other = m0>0 & m0~=seSel;
df0(m0Other) = nan;
df0ip = df0;
df0NanMap = sum(isnan(df0),3);
[ih,iw] = find(df0NanMap>0);
for ii=1:numel(ih)
    %if mod(ii,100000)==0; fprintf('%d\n',ii); end
    ih0 = ih(ii);
    iw0 = iw(ii);
    x0 = squeeze(df0(ih0,iw0,:));
    for tt=2:T0
        if isnan(x0(tt))
            x0(tt) = x0(tt-1);
        end
    end
    for tt=T0-1:-1:1
        if isnan(x0(tt))
            x0(tt) = x0(tt+1);
        end
    end
    x0i = x0;
    df0ip(ih0,iw0,:) = x0i;
end
df0ip(isnan(df0ip)) = 0;

% ----------------------------------------------------------------
% emphasize on the bright parts
% propagation in bright pixels need less area to be considered as significant
s00 = sqrt(varEst);
thrMax = ceil(quantile(df0ip(:),0.99)/s00);
dFx = df0ip;
Sx = 1*(m0==seSel);

thrVec = 0:thrMax;
% thrVec = 0;

tMapMT = gtw.getMovPixelMapMultiThr(dFx,Sx,thrVec,s00);
% tMapMT = burst.getSuperEventRisingMapMultiThr(dFx,Sx,thrVec,s00);

nThr = numel(thrVec);
intMap = nan(H0,W0);
areaPerThr = zeros(nThr,1);
% baseSz = 10;
for ii=nThr:-1:1
    %minSz = (nThr+1-ii)*baseSz;
    minSz = 4;
    newMap = ~isnan(tMapMT(:,:,ii)) & isnan(intMap);
    newMap = bwareaopen(newMap,minSz,4);
    
    % fill small holes
    newMapfh = imfill(newMap,'holes');
    xHoles = newMapfh - newMap;
    xHolesBig = bwareaopen(xHoles,minSz,4);
    xHolesSmall = xHoles - xHolesBig;
    xHolesSmall(intMap>0) = 0;
    newMap(xHolesSmall>0) = true;
    
    areaPerThr(ii) = sum(newMap(:));
    intMap(newMap) = ii;
end
% ov1 = plt.regionMapWithData(uint32(intMap),intMap*0,0.4); zzshow(ov1);

% ----------------------------------------------------------------
% super pixels

if riseOnly>0
    nNodeUB = round(100*100*100/T0);
else
    nNodeUB = round(100*100*70/T0);
end
spSzBase = max(sum(areaPerThr./(nThr:-1:1)')/nNodeUB,8);
spSz = spSzBase*(nThr:-1:1)';

spSeedMap = zeros(H0,W0);
spMapUsed = zeros(H0,W0);
dfm = nanmean(df0ip,3);
dfmMed = medfilt2(dfm);
% if 1
% get seeds at different levels
for ii=nThr:-1:1
    mapCur = intMap==ii;
    if max(mapCur(:))>0
        A = dfmMed;
        nx = round(H0*W0/spSz(ii));
        L0 = superpixels(A,nx);
        spLst0 = label2idx(L0);
        for jj=1:numel(spLst0)
            pix00 = spLst0{jj};
            [ih00,iw00] = ind2sub([H0,W0],pix00);
            sh00 = round(mean(ih00));
            sw00 = round(mean(iw00));
            nUsed = sum(spMapUsed(pix00)>0);
            usedRatio = nUsed/numel(pix00);
            rgh1 = max(sh00-1,1):min(sh00+1,H0);
            rgw1 = max(sw00-1,1):min(sw00+1,W0);
            nb0 = spMapUsed(rgh1,rgw1);
            if sum(intMap(pix00)==ii)>0 && sum(nb0(:))==0 && usedRatio<0.5
            %if intMap(sh00,sw00)==ii && sum(nb0(:))==0 && usedRatio<0.5
                spSeedMap(sh00,sw00) = ii;
                spMapUsed(pix00) = 1;
            end
        end
    end
end

if sum(spSeedMap(:))==0
    keyboard
end

% assign pixels to seeds
nPix = H0*W0;
kDist = 1;
kInt = 10;  % weight for intensity distance
nNeib = 5;
pNeib = nan(nPix,nNeib);  % neighbor seed index of each pixel
pWeit = nan(nPix,nNeib);  % weight to neighbor seeds
[sh,sw] = find(spSeedMap>0);
pixMap = zeros(H0,W0);
pixMap(:) = 1:nPix;
for ii=1:numel(sh)
    %if mod(ii,1000)==0; fprintf('%d\n',ii); end
    sh0 = sh(ii);
    sw0 = sw(ii);
    
    lvl0 = max(intMap(sh0,sw0),1);
    sz0 = spSz(lvl0);
    gaphw = ceil(sqrt(sz0));
    
    % pixels near a seed
    rgh = max(sh0-gaphw,1):min(sh0+gaphw,H0);
    rgw = max(sw0-gaphw,1):min(sw0+gaphw,W0);
    pix0 = reshape(pixMap(rgh,rgw),[],1);
    [pixh,pixw] = ind2sub([H0,W0],pix0);
    
    % distances
    dEuc = sqrt((sh0-pixh).^2+(sw0-pixw).^2);
    dInt = abs(dfm(sh0,sw0) - dfm(pix0));
    dWeit = 1./max(kDist*dEuc + kInt*dInt,0.00001);
    
    % assign seed to pixels
    %seedPos = pixMap(sh0,sw0);
    for jj=1:numel(pix0)
        pix00 = pix0(jj);
        nx = pNeib(pix00,:);
        wx = pWeit(pix00,:);
        loc00 = find(isnan(nx),1);
        if isempty(loc00)
            [xMin,ixMin] = nanmin(wx);
            if xMin<dWeit(jj)
                nx(ixMin) = ii;
                wx(ixMin) = dWeit(jj);
            end
        else
            nx(loc00) = ii;
            wx(loc00) = dWeit(jj);
        end
        pNeib(pix00,:) = nx;
        pWeit(pix00,:) = wx;
    end
end
pNeib(isnan(pNeib)) = 0;
pWeit(isnan(pWeit)) = 0;

[~,ix] = max(pWeit,[],2);
pNeib1 = pNeib';
lbl0 = pNeib1(5*(0:(nPix-1))+ix')';
% lbl0 = spIdxMap(lbl0);
spMap1 = zeros(H0,W0);
spMap1(:) = lbl0;
% vMap0di = imdilate(vMap0>0,strel('square',5));
% spMap1(vMap0di==0) = 0;

spLst = label2idx(spMap1);
spLst = spLst(~cellfun(@isempty,spLst));

if 0
    ov1 = plt.regionMapWithData(uint32(spMap1),spMap1*0,0.3);
    tmp = ov1(:,:,1); tmp(spSeedMap>0) = 255; ov1(:,:,1) = tmp;
    tmp = ov1(:,:,2); tmp(spSeedMap>0) = 0; ov1(:,:,2) = tmp;
    tmp = ov1(:,:,3); tmp(spSeedMap>0) = 0; ov1(:,:,3) = tmp;
    zzshow(ov1);
end

end



