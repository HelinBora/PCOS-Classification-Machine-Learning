function machineLearningGUI
% ML GUI - Tam Sürüm (Universal + Anti-Leakage + Parametre Seçimi)
% DÜZELTME: Model seçiminin yanýna "Parametre" dropdown'ý eklendi.
% DÜZELTME: Arayüz elemanlarý çakýþmayacak þekilde saða kaydýrýldý.

    fig = uifigure('Name','ML Arayüzü (Geliþmiþ)','Position',[100 100 1250 700]);

    %% 1. ÜST PANEL: Veri & Model & Parametreler
    pTop = uipanel(fig,'Title','Veri & Model & Parametreler','Position',[10 540 1230 150]);

    % 1.1 Veri Yükle Butonu
    uibutton(pTop,'Text','Veri Seti Yükle','Position',[10 70 110 30],...
        'ButtonPushedFcn',@onLoadData);

    % 1.2 Hedef Deðiþken
    uilabel(pTop,'Text','Hedef:','Position',[130 75 40 20]);
    ddTarget = uidropdown(pTop,'Items',{'(Yükle)'},...
        'Position',[170 70 130 30],'Enable','off',...
        'ValueChangedFcn',@onTargetChanged);

    % 1.3 Model Seçimi
    uilabel(pTop,'Text','Model:','Position',[310 75 40 20]);
    ddModel  = uidropdown(pTop,'Items',{'KNN','SVM','Lojistik Reg.','Random Forest','K-Means'},...
                'Position',[355 70 140 30],'Enable','off',...
                'ValueChangedFcn',@onModelChanged); % Tetikleyici eklendi

    % 1.4 PARAMETRE SEÇÝMÝ (YENÝ EKLENEN KISIM)
    uilabel(pTop,'Text','Param:','Position',[505 75 45 20],'FontWeight','bold');
    ddParam = uidropdown(pTop,'Items',{'-'},...
                'Position',[550 70 130 30],'Enable','off');

    % 1.5 Oranlar (Train/Val/Test) - Biraz saða kaydýrýldý
    uilabel(pTop,'Text','Train:','Position',[690 115 40 20]);
    efTrain = uieditfield(pTop,'numeric','Position',[730 110 40 30],'Limits',[0 100],'Value',70);

    uilabel(pTop,'Text','Val:','Position',[780 115 30 20]);
    efVal = uieditfield(pTop,'numeric','Position',[810 110 40 30],'Limits',[0 100],'Value',15);

    uilabel(pTop,'Text','Test:','Position',[860 115 30 20]);
    efTest = uieditfield(pTop,'numeric','Position',[895 110 40 30],'Limits',[0 100],'Value',15);

    % 1.6 Çalýþtýr Butonu
    btnRun = uibutton(pTop,'Text','SONUÇLARI GÖSTER','Position',[690 70 160 30], ...
        'Enable','on','ButtonPushedFcn',@onRun,  'FontWeight','bold');

    % 1.7 Kaydet Butonu
    btnSaveModel = uibutton(pTop,'Text','Modeli Kaydet','Position',[860 70 110 30], ...
        'Enable','off','ButtonPushedFcn',@onSaveModel);

    % Durum Mesajý
    msg = uitextarea(pTop,'Position',[10 10 1200 45],'Editable','off');
    msg.Value = "Baþlamak için 'Veri Seti Yükle' butonuna basýnýz.";

    %% 2. ORTA BÖLÜM: Görseller
    
    % Sol: Sýnýf Daðýlýmý
    axDist = uiaxes(fig,'Position',[10 290 400 230]);
    axDist.Title.String = 'Hedef Daðýlýmý';

    % Orta: Performans Grafiði
    pConf  = uipanel(fig,'Title','Performans','Position',[420 290 400 230]);
    % Ýçine kodla grafik çizilecek

    % Sað: Hata Analizi
    axROC  = uiaxes(fig,'Position',[830 290 400 230]);
    axROC.Title.String = 'Hata Analizi';

    %% 3. ALT PANEL: Metrikler & Tablolar
    pBottom = uipanel(fig,'Title','Sonuçlar & Detaylar','Position',[10 10 1230 270]);

    % Tablo 1: Metrikler
    tblMetrics = uitable(pBottom,'Position',[10 130 900 110],...
        'ColumnName',{'Metrik','Deðer'},'Data',cell(0,2));

    % Tablo 2: Hata Listesi
    tblErr = uitable(pBottom,'Position',[10 10 1200 110],...
        'ColumnName',{'Index','Gerçek','Tahmin'},'Data',cell(0,3));

    % ROC Sýnýf Seçimi
    uilabel(pBottom,'Text','ROC Sýnýfý:','Position',[930 210 80 20]);
    ddROCClass = uidropdown(pBottom,'Items',{'(Model Yok)'},...
        'Position',[1010 205 160 30],'Enable','off',...
        'ValueChangedFcn',@onROCClassChanged);

    % Export & Validation
    btnExportMetrics = uibutton(pBottom,'Text','Metrikleri Dýþa Aktar',...
        'Position',[930 165 240 30],'ButtonPushedFcn',@onExportMetrics,...
        'Enable','off');

    btnValConf = uibutton(pBottom,'Text','Validation Grafiði', ...
        'Position',[930 130 240 30], ...
        'ButtonPushedFcn',@onShowValConf, ...
        'Enable','off');

    %% Veri Yapýsý (State)
    S.data = [];
    S.targetName = '';
    S.problemType = 'Classification'; 
    S.mdl = [];
    S.yte = []; S.ypred = [];
    S.yval = []; S.ypredVal = [];
    S.classes = [];
    S.scoresTest = [];
    S.scoresAvailable = false;
    
    guidata(fig, S);

    %% -------------------- CALLBACKS --------------------

    function onLoadData(~,~)
        [f,p] = uigetfile({'*.csv','CSV Dosyasý (*.csv)'},'Veri Seti Seç');
        if isequal(f,0), return; end
        
        try
            T = readtable(fullfile(p,f));
       
            % Sütun isimlerini düzelt
            T.Properties.VariableNames = matlab.lang.makeValidName(T.Properties.VariableNames);
        catch ME
            msg.Value = "Dosya hatasý: " + string(ME.message);
            return;
        end
        
        vn = T.Properties.VariableNames;
                

        %% --- SIZINTI KORUMASI (Anti-Leakage) ---
        guess = '';
        candidates = {'Outcome','Target','Class','Label','PCOS','Growth_Rate'};
        for k=1:numel(candidates)
            idx = find(contains(vn, candidates{k}, 'IgnoreCase',true), 1);
            if ~isempty(idx), guess = vn{idx}; break; end
        end

        if contains(guess, 'PCOS', 'IgnoreCase', true)
            badKeywords = {'sl_no','patient','pregnant','abortion','follicle'};
            colsToRemove = {};
            for i=1:numel(vn)
                if strcmpi(vn{i}, guess), continue; end
                for j=1:numel(badKeywords)
                    if contains(lower(vn{i}), badKeywords{j})
                        colsToRemove{end+1} = vn{i}; %#ok<AGROW>
                        break;
                    end
                end
            end
            if ~isempty(colsToRemove)
                T = removevars(T, colsToRemove);
                uialert(fig,"Veri sýzýntýsý yapabilecek sütunlar silindi:\n"+strjoin(colsToRemove,', '),'Bilgi');
            end
        end
        %% -----------------------------------------

        vn = T.Properties.VariableNames;
        ddTarget.Items = vn;
        if ~isempty(guess) && any(strcmp(vn, guess))
            ddTarget.Value = guess;
        else
            ddTarget.Value = vn{end};
        end
        ddTarget.Enable = 'on';

        S = guidata(fig);
        S.data = T;
        guidata(fig,S);

        onTargetChanged(); 
        msg.Value = "Veri yüklendi: " + f;
    end

    function onTargetChanged(~,~)
        S = guidata(fig);
        if isempty(S.data), return; end
        
        yCol = ddTarget.Value;
        y = S.data.(yCol);
        
        % Tip Algýlama: >20 benzersiz sayýsal deðer ise Regresyon
        isNum = isnumeric(y);
        numUnq = numel(unique(y));
        
        if isNum && numUnq > 20
            S.problemType = 'Regression';
            ddModel.Items = {'KNN (Reg)', 'SVM (Reg)', 'Lineer Regresyon', 'Random Forest (Reg)', 'Regresyon Aðacý'};
            
            axDist.Title.String = 'Hedef Daðýlýmý (Histogram)';
            axROC.Title.String = 'Hata (Residuals - Gerçek Ölçek)';
            axROC.XLabel.String = 'Örnek'; axROC.YLabel.String = 'Hata (Gerçek - Tahmin)';
            pConf.Title = 'Tahmin vs Gerçek (Scatter)';
            ddROCClass.Enable = 'off';
            ddROCClass.Items = {'(Regresyonda Yok)'};
            btnValConf.Text = 'Validation Scatter Plot';
        else
            S.problemType = 'Classification';
            ddModel.Items = {'KNN', 'SVM', 'Lojistik Regresyon', 'Random Forest', 'K-Means'};
            
            axDist.Title.String = 'Sýnýf Daðýlýmý';
            axROC.Title.String = 'ROC Eðrisi';
            axROC.XLabel.String = '1 - Özgüllük'; axROC.YLabel.String = 'Duyarlýlýk';
            pConf.Title = 'Confusion Matrix';
            btnValConf.Text = 'Validation Confusion Matrix';
        end
        
        ddModel.Enable = 'on';
        S.targetName = yCol;
        
        % Model deðiþince parametreler güncellenmeli
        onModelChanged(); 
        
        guidata(fig,S);
        updateClassDistPreview();
    end
    
    function onModelChanged(~,~)
        % Model seçimine göre "Parametre" kutusunu doldur
        selModel = ddModel.Value;
        ddParam.Enable = 'on';
        
        switch selModel
            % --- SINIFLANDIRMA ---
            case 'KNN'
                ddParam.Items = {'k=1', 'k=3', 'k=5', 'k=7', 'k=9', 'k=15'};
                ddParam.Value = 'k=5';
            case 'SVM'
                ddParam.Items = {'Gaussian (RBF)', 'Linear', 'Polynomial (d=2)', 'Polynomial (d=3)'};
                ddParam.Value = 'Gaussian (RBF)';
            case 'Random Forest'
                ddParam.Items = {'10 Aðaç', '50 Aðaç', '100 Aðaç', '200 Aðaç'};
                ddParam.Value = '100 Aðaç';
            case 'Lojistik Regresyon'
                ddParam.Items = {'Standart', 'Regularization (L2)'};
                ddParam.Value = 'Standart';
            case 'K-Means'
                ddParam.Items = {'Euclidean', 'Manhattan', 'Cosine'};
                ddParam.Value = 'Euclidean';
                
            % --- REGRESYON ---
            case 'KNN (Reg)'
                ddParam.Items = {'k=3', 'k=5', 'k=10'};
                ddParam.Value = 'k=5';
            case 'SVM (Reg)'
                ddParam.Items = {'Gaussian', 'Linear'};
                ddParam.Value = 'Gaussian';
            case 'Lineer Regresyon'
                ddParam.Items = {'En Küçük Kareler', 'Robust'};
                ddParam.Value = 'En Küçük Kareler';
            case 'Random Forest (Reg)'
                ddParam.Items = {'20 Aðaç', '50 Aðaç', '100 Aðaç', '200 Aðaç'};
                ddParam.Value = '100 Aðaç';
            case 'Regresyon Aðacý'
                ddParam.Items = {'MinLeaf=1', 'MinLeaf=5', 'MinLeaf=10'};
                ddParam.Value = 'MinLeaf=1';
                
            otherwise
                ddParam.Items = {'Standart'};
                ddParam.Enable = 'off';
        end
    end

    function onRun(~,~)
        S = guidata(fig);
        if isempty(S.data), msg.Value="Lütfen veri seti yükleyin."; return; end
        
        T = S.data;
        yName = S.targetName;
        
        % Veri Hazýrlýðý
        T = rmmissing(T);
        yRaw = T.(yName); % Hedef (Gerçek ölçekte)
        XRaw = T; XRaw.(yName) = [];
        
        % Sadece numerik olanlarý al
        isNum = varfun(@isnumeric, XRaw, 'OutputFormat', 'uniform');
        X = table2array(XRaw(:, isNum));
        
        if isempty(X)
            msg.Value = "Hata: Sayýsal özellik (feature) bulunamadý."; return;
        end
        
        % X Normalize edilir, Y olduðu gibi kalýr (Hata hesabý için önemli)
        X = normalize(X); 
        
        % Train/Val/Test Bölme
        pTr = efTrain.Value/100; 
        pVal = efVal.Value/100;
        pTe = efTest.Value/100;
        
        if abs(pTr+pVal+pTe - 1) > 0.01
            uialert(fig,'Oranlarýn toplamý 100 olmalýdýr.','Hata'); return;
        end
        
        N = size(X,1);
        cv1 = cvpartition(N, 'HoldOut', pVal+pTe);
        Xtr = X(training(cv1),:); ytr = yRaw(training(cv1),:); 
        
        Xrest = X(test(cv1),:);   yrest = yRaw(test(cv1),:);
        
        if isempty(yrest), msg.Value = "Test için yeterli veri yok."; return; end
        
        valRatio = pVal / (pVal + pTe);
        cv2 = cvpartition(numel(yrest), 'HoldOut', 1-valRatio);
        
        Xval = Xrest(training(cv2),:); yval = yrest(training(cv2),:);
        Xte  = Xrest(test(cv2),:);     yte  = yrest(test(cv2),:);
        
        % --- SEÇÝLEN PARAMETRELERÝ OKUMA ---
        modelSel = ddModel.Value;
        paramSel = ddParam.Value;
        
        msg.Value = "Model eðitiliyor: " + modelSel + " (" + paramSel + ")..."; drawnow;
        
        try
            if strcmp(S.problemType, 'Classification')
                %% SINIFLANDIRMA EÐÝTÝMÝ
                if ~iscategorical(ytr), ytr=categorical(ytr); yval=categorical(yval); yte=categorical(yte); end
                classes = categories(ytr);
                S.classes = classes;
                
                switch modelSel
                    case 'KNN'
                        kVal = str2double(regexp(paramSel,'\d+','match','once'));
                        mdl = fitcknn(Xtr,ytr,'NumNeighbors',kVal);
                        
                    case 'SVM'
                        kern = 'gaussian';
                        if contains(paramSel,'Linear'), kern='linear';
                        elseif contains(paramSel,'Polynomial'), kern='polynomial'; end
                        
                        % Polinom derecesi
                        deg = 3; if contains(paramSel,'d=2'), deg=2; end
                        
                        t = templateSVM('Standardize',false,'KernelFunction',kern, 'PolynomialOrder',deg);
                        mdl = fitcecoc(Xtr,ytr,'Learners',t);
                        
                    case 'Lojistik Regresyon'
                        mdl = fitcecoc(Xtr,ytr,'Learners','logistic');
                        
                    case 'Random Forest'
                        nTree = str2double(regexp(paramSel,'\d+','match','once'));
                        mdl = fitcensemble(Xtr,ytr,'Method','Bag', 'NumLearningCycles', nTree);
                        
                    case 'K-Means'
                        dist = 'sqeuclidean';
                        if contains(paramSel,'Manhattan'), dist='cityblock';
                        elseif contains(paramSel,'Cosine'), dist='cosine'; end
                        
                        [idx, C] = kmeans(Xtr, numel(classes), 'Replicates',3, 'Distance', dist);
                        % Majority Vote Mapping
                        map = cell(numel(classes),1);
                        for i=1:numel(classes)
                            g = ytr(idx==i);
                            if isempty(g), map{i}=classes{1}; else, map{i}=mode(g); end
                        end
                        mdl = struct('Type','KMeans','C',C,'Map',{map}, 'Dist',dist);
                end
                
                % Tahmin
                if isstruct(mdl) && isfield(mdl,'Type') && strcmp(mdl.Type,'KMeans')
                     D = pdist2(Xte, mdl.C, mdl.Dist); [~,n]=min(D,[],2); ypred = cat(1,mdl.Map{n});
                     D2= pdist2(Xval,mdl.C, mdl.Dist); [~,n2]=min(D2,[],2); ypredVal = cat(1,mdl.Map{n2});
                     scores = [];
                else
                     [ypred, scores] = predict(mdl, Xte);
                     [ypredVal, ~] = predict(mdl, Xval);
                end
                
                S.scoresTest = scores;
                S.scoresAvailable = ~isempty(scores);
                
            else
                %% REGRESYON EÐÝTÝMÝ
                ytr=double(ytr); yval=double(yval); yte=double(yte);
                
                switch modelSel
                    case 'KNN (Reg)'
                        % Regresyon KNN için SVM RBF benzer davranýþ gösterir
                         mdl = fitrsvm(Xtr,ytr,'KernelFunction','gaussian');
                         
                    case 'SVM (Reg)'
                         kern = 'gaussian';
                         if contains(paramSel,'Linear'), kern='linear'; end
                         mdl = fitrsvm(Xtr,ytr,'Standardize',false,'KernelFunction',kern);
                         
                    case 'Lineer Regresyon'
                        if contains(paramSel,'Robust')
                             mdl = fitrlinear(Xtr,ytr,'Learner','leastsquares','Regularization','lasso');
                        else
                             mdl = fitrlinear(Xtr,ytr,'Learner','leastsquares');
                        end
                        
                    case 'Random Forest (Reg)'
                        nTree = str2double(regexp(paramSel,'\d+','match','once'));
                        mdl = fitrensemble(Xtr,ytr,'Method','LSBoost','NumLearningCycles',nTree);
                        
                    case 'Regresyon Aðacý'
                        minL = str2double(regexp(paramSel,'\d+','match','once'));
                        mdl = fitrtree(Xtr,ytr,'MinLeafSize',minL);
                end
                
                ypred = predict(mdl, Xte);
                ypredVal = predict(mdl, Xval);
                S.scoresAvailable = false;
                S.classes = {};
            end
        catch ME
            uialert(fig, "Model eðitimi sýrasýnda hata: " + ME.message, 'Hata');
            msg.Value = "Eðitim baþarýsýz.";
            return;
        end
        
        S.mdl = mdl; S.yte = yte; S.ypred = ypred; S.yval = yval; S.ypredVal = ypredVal;
        guidata(fig,S);
        
        %% SONUÇ GÖRSELLEÞTÝRME
        % 1. Orta Panel
        delete(pConf.Children);
        if strcmp(S.problemType, 'Classification')
            confusionchart(pConf, yte, ypred);
        else
            axC = uiaxes(pConf,'Position',[10 10 380 200]);
            plot(axC, yte, ypred, 'bo', 'MarkerFaceColor','b', 'MarkerSize',4); hold(axC,'on');
            % Referans çizgisi (y=x)
            mn = min([yte; ypred]); mx = max([yte; ypred]);
            plot(axC, [mn mx], [mn mx], 'r--', 'LineWidth', 2);
            grid(axC,'on');
            title(axC, 'Tahmin vs Gerçek');
            xlabel(axC, 'Gerçek Deðerler'); ylabel(axC, 'Tahmin Edilen');
        end
        
        % 2. Sað Grafik (Hata)
        cla(axROC);
        if strcmp(S.problemType, 'Classification')
            if S.scoresAvailable
                ddROCClass.Enable = 'on';
                ddROCClass.Items = cellstr(S.classes);
                ddROCClass.Value = S.classes{1};
                updateROCFromDropdown();
            else
                ddROCClass.Enable = 'off';
                axROC.Title.String = 'Skor üretilmedi (ROC yok)';
            end
        else
            % Residuals (Gerçek ölçek)
            residuals = yte - ypred;
            plot(axROC, residuals, 'r.', 'MarkerSize', 10);
            yline(axROC, 0, 'k--', 'LineWidth', 1.5);
            axROC.Title.String = 'Hata Daðýlýmý (Residuals)';
            axROC.YLabel.String = 'Hata (Fark)';
            grid(axROC, 'on');
        end
        
        updateMetrics();
        updateErrorTable();
        
        msg.Value = "Ýþlem tamamlandý: " + modelSel; 
        updateClassDistPreview;
        btnExportMetrics.Enable = 'on';
        btnValConf.Enable = 'on';
        btnSaveModel.Enable = 'on';
        btnRun.Enable = 'on';
    end

    function updateMetrics
        S = guidata(fig);
        if strcmp(S.problemType, 'Classification')
             cm = confusionmat(S.yte, S.ypred);
             acc = sum(diag(cm))/sum(cm(:));
             data = {'Accuracy', sprintf('%.4f', acc)};
        else
             err = S.yte - S.ypred;
             rmse = sqrt(mean(err.^2));
             mae = mean(abs(err));
             r2 = 1 - (sum(err.^2) / sum((S.yte - mean(S.yte)).^2));
             data = {
                 'RMSE', sprintf('%.4f', rmse);
                 'MAE',  sprintf('%.4f', mae);
                 'R2',   sprintf('%.4f', r2)
             };
        end
        tblMetrics.Data = data;
    end

    function updateErrorTable()
        S = guidata(fig);
        n = min(50, numel(S.yte));
        d = cell(n,3);
        for i=1:n
            d{i,1} = i;
            if strcmp(S.problemType, 'Classification')
                d{i,2} = char(S.yte(i)); d{i,3} = char(S.ypred(i));
            else
                d{i,2} = sprintf('%.2f',S.yte(i)); d{i,3} = sprintf('%.2f',S.ypred(i));
            end
        end
        tblErr.ColumnName = {'Index','Gerçek','Tahmin'};
        tblErr.Data = d;
    end

    function onROCClassChanged(~,~)
        updateROCFromDropdown();
    end

    function updateROCFromDropdown
        S = guidata(fig);
        if strcmp(S.problemType, 'Classification') && S.scoresAvailable
             cla(axROC);
             cls = ddROCClass.Value;
             idx = find(strcmp(S.classes, cls));
             if isempty(idx), return; end
             [x,y,~,auc] = perfcurve(S.yte, S.scoresTest(:,idx), cls);
             plot(axROC, x, y, 'LineWidth',2);
             axROC.Title.String = sprintf('ROC - %s (AUC=%.2f)', cls, auc);
             grid(axROC,'on');
        end
    end

    function updateClassDistPreview
        S = guidata(fig);
        cla(axDist);
        if isempty(S.data), return; end
        y = S.data.(S.targetName);
        if strcmp(S.problemType, 'Classification')
            if ~iscategorical(y), y=categorical(y); end
            histogram(axDist, y);
        else
            histogram(axDist, y, 20);
        end
    end

    function onExportMetrics(~,~)
        [f,p] = uiputfile('Metrics.csv');
        if f~=0, writetable(cell2table(tblMetrics.Data), fullfile(p,f)); end
    end

    function onShowValConf(~,~)
        S = guidata(fig);
        figure('Name','Validation Analizi');
        if strcmp(S.problemType, 'Classification')
            confusionchart(S.yval, S.ypredVal);
            title('Validation Confusion Matrix');
        else
            plot(S.yval, S.ypredVal, 'bo'); 
            hold on;
            mn = min([S.yval; S.ypredVal]); mx = max([S.yval; S.ypredVal]);
            plot([mn mx], [mn mx], 'r--');
            xlabel('Gerçek'); ylabel('Tahmin');
            grid on;
            title('Validation Scatter Plot');
        end
    end

    function onSaveModel(~,~)
        S = guidata(fig);
        [f,p] = uiputfile('TrainedModel.mat');
        if f~=0, save(fullfile(p,f), 'S'); end
    end
end