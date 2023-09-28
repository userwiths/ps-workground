$global:productLimit = 50;
$global:cmsPageLimit = 50;
$global:categoryLimit = 10;

# Get first argument as url
$url = $args[0];
$username = "dummy";
if($args[1]) {
    $username = $args[1];
}
$password = "Qwerty_2_Qwerty";
if($args[2]) {
    $password = $args[2];
}

# Non-Magento related.
function Check-SSHAvailability () {
    $names = (Get-Command New-PSSession).ParameterSets.Name;
    if ( $names -contains "SSHHost" ) {
        Write-Host "SSH is available";
    } else {
        Write-Host "SSH is not available";
    }
};

# Stand alone and helpers
function Add-MagentoPagination () {
    param (
        [String] $Url = "http://localhost",
        [Int] $PageSize = 10,
        [Int] $Page = 1
    );

    if ( $Url[-1] -ne "&" ) {
        $Url += "&";
    }
    $Url += [URI]::EscapeDataString("searchCriteria[pageSize]") + "=$PageSize";
    $Url += "&" + [URI]::EscapeDataString("searchCriteria[currentPage]") + "=$Page";
    return $Url;
}
function Format-MagentoSearchCriteria () {
    param (
        [String] $Url = "http://localhost",
        [Hashtable] $SearchCriteria
    );

    if ( $Url[-1] -ne "/" ) {
        $Url += "/?";
    }

    $keys = $SearchCriteria.searchCriteria.filterGroups.filters.keys;
    foreach($key in $keys) {
        $Url += [URI]::EscapeDataString("searchCriteria[filterGroups][0][filters][0][$key]") + "=$($searchCriteria.searchCriteria.filterGroups.filters.$key)";
        if ( $key -ne $keys[-1] ) {
            $Url += "&";
        }
    }
    return $Url;
}
function Get-MagentoToken () {
    param (
        [String] $Url = "http://localhost",
        [String] $Username = "dummy",
        [String] $Password = "Qwerty_2_Qwerty"
    );
    $apiUrl = "$Url/rest/V1/integration/admin/token";
    $token = Invoke-RestMethod -Method Post -Uri $apiUrl -Body (@{username=$Username;password=$Password;} | ConvertTo-Json -Depth 5) -ContentType "application/json";
    Write-Host "Token: $token";
    # Convert to secure string
    return $(ConvertTo-SecureString $token -AsPlainText -Force);
}
#

function Get-MagentoModules ($url, $params) {
    $recomendedModules = @(
        @{
            name = "Mageplaza_Smtp";
            reason = "Adds Abandoned cart and more settings for the email server.";
        }, @{
            name = "Mageplaza_CurrencyFormatter";
            reason = "Allows chaning currency display and fixes a buggy space that appears on a lot of projects in the price.";
        }, @{
            name = "Magefan_WysiwygAdvanced";
            reason = "Adds needed functionality to WYSIWYG editor, like changing Fonts.";
        }, @{
            name = "Magefan_RocketJavascript";
            reason = "Improves site performance in PageSpeed metrics.";
        }, @{
            name = "Swissup_Firecheckout";
            reason = "Improves checkout process.";
        }, @{
            name = "Swissup_AddressFieldManager";
            reason = "Allows adding new address fields from admin panel and managing them.";
        }, @{
            name = "Swissup_CheckoutFields";
            reason = "Allows adding new checkout fields from admin panel and managing them.";
        }, @{
            name = "Swissup_CustomerFieldManager";
            reason = "Allows adding new customer fields from admin panel and managing them.";
        }, @{
            name = "Amasty_Shopby";
            reason = "Better layered navigation and a price slider for it.";
        }
    );

    $apiUrl = "$url/rest/all/V1/modules";
    $params.Uri = $apiUrl;
    $modules = Invoke-RestMethod @params;

    # Check for missing recomended modules
    foreach ($recomendedModule in $recomendedModules) {
        $module = $modules | Where-Object {$_ -eq $recomendedModule.name};
        if ($module -eq $null) {
            Write-Host "Missing recomended module: $($recomendedModule.name)";
            Write-Host "Reason for wanting this module: $($recomendedModule.reason)";
            Write-Host "";
        }
    }
    #return $modules;
}
function Get-StoreConfig ($url, $params) {
    $apiUrl = "$url/rest/V1/store/storeConfigs";
    $params.Uri = $apiUrl;
    $storeConfigs = Invoke-RestMethod @params;
    return $storeConfigs;
}
function Get-AllowedCountires ($url, $params) {
    $apiUrl = "$url/rest/V1/directory/countries";
    $params.Uri = $apiUrl;
    $countires = Invoke-RestMethod @params;
    return $countires;
}
function Get-AllowedCurrency ($url, $params) {
    $apiUrl = "$url/rest/V1/directory/currency";
    $params.Uri = $apiUrl;
    $currency = Invoke-RestMethod @params;
    return $currency;
}
function Get-MagentoCategories ($url, $params) {
    $apiUrl = "$url/rest/V1/categories/list";
    $searchCriteria = @{searchCriteria=@{filterGroups=@{filters=@{field="is_active";value="1";conditionType="eq"}};sortOrders=@{field="name";direction="ASC"}}; pageSize=10; currentPage=1};

    $apiUrl = Format-MagentoSearchCriteria -Url $apiUrl -SearchCriteria $searchCriteria;
    $apiUrl = Add-MagentoPagination -Url $apiUrl -PageSize 10 -Page 1;

    $params.Uri = $apiUrl;
    $params.Body = @{};
    $categories = Invoke-RestMethod @params;
    
    $categoryUrls = @();
    $categories = $categories.items;
    foreach ($category in $categories) {
        $customAttributes = $category.custom_attributes;
        foreach ($customAttribute in $customAttributes) {
            if ($customAttribute.attribute_code -eq "url_key") {
                $categoryUrls += "$url/$($customAttribute.value).html";
            }
            if( $categoryUrls.length -gt $global:categoryLimit ) {
                break;
            }
        }
    }
    return $categoryUrls;
}
function Get-MagentoProducts ($url, $params) {
    $apiUrl = "$url/rest/V1/products";
    $searchCriteria = @{
        searchCriteria=@{
            filterGroups=[PSCustomObject]@{
                filters=@{
                    field="status";
                    value="1";
                    conditionType="eq";
                }
            };
            sortOrders=@{
                field="name";
                direction="ASC";
            };
            pageSize=10; 
            currentPage=1
        }
    };

    $apiUrl = Format-MagentoSearchCriteria -Url $apiUrl -SearchCriteria $searchCriteria;
    $apiUrl = Add-MagentoPagination -Url $apiUrl -PageSize 10 -Page 1;

    $params.Uri = $apiUrl;
    $params.ContentType = "application/x-www-url-form-encoded;charset=UTF-8";
    $params.Body = @{};
    $products = Invoke-RestMethod @params;
    $productUrls = @();
    $products = $products.items;
    foreach ($product in $products) {
        $customAttributes = $product.custom_attributes;
        foreach ($customAttribute in $customAttributes) {
            if( $productUrls.length -gt $global:productLimit ) {
                break;
            }
            if ($customAttribute.attribute_code -eq "url_key") {
                $productUrls += "$url/$($customAttribute.value).html";
                break;
            }
        }
    }
    return $productUrls;
}
function Get-MagentoUrlSummary () {
    param (
        [Array] $urlsToCheck,
        [Array] $categoryUrls,
        [Array] $productUrls,
        [Array] $pagesUrls
    );
    $summary = @();
    $counter = 1;
    foreach ($urlToCheck in $urlsToCheck) {
        $response = Invoke-WebRequest -Uri $urlToCheck -Method Get -MaximumRedirection 1 -SkipHttpErrorCheck -ErrorAction SilentlyContinue -ErrorVariable err;
        # $err contains info bout the issue;
        if ($response.StatusCode -ne 200) {
            # TODO: type is not detected correctly due to `.html` in some urls.
            $temp = @{
                url = $urlToCheck;
                status = $response.StatusCode;
                error = $err;
            };
            if ( $productUrls.Contains($urlToCheck) -or $productUrls.Contains("$urlToCheck.html") ) {
                $temp.type = "product";
            } elseif ( $categoryUrls.Contains($urlToCheck) -or $categoryUrls.Contains("$urlToCheck.html") ) {
                $temp.type = "category";
            } elseif ( $pagesUrls.Contains($urlToCheck) -or $pagesUrls.Contains("$pagesUrls.html") ) {
                $temp.type = "cms page";
            } else {
                $temp.type = "other";
            }
            $summary += $temp;
        }

        # Add progress bar
        Write-Progress -Activity "Checking urls" -Status "Checked $($counter) of $($urlsToCheck.length)" -PercentComplete ($counter / $urlsToCheck.length * 100);
        $counter++;
    }
    return $summary;
}
function Get-LowStockProducts () {
    param (
        [String] $Url = "http://localhost",
        [Hashtable] $params,
        [Int] $Qty = 5,
        [Int] $PageSize = 10,
        [Int] $Page = 1
    );
    $apiUrl = "$url/rest/all/V1/stockItems/lowStock";
    $searchCriteria = @{scopeId=0;qty=$Qty;pageSize=$PageSize;currentPage=$Page};
    $params.Uri = $apiUrl;
    $params.Body = $searchCriteria;
    $products = Invoke-RestMethod @params;
    Write-Host "There are $($products.total_count) items under $Qty qty.";
    return $products;
}
function Check-MagentoUrls () {
    param (
        [String] $Url = "http://localhost",
        [String] $Username = "dummy",
        [String] $Password = "Qwerty_2_Qwerty",
        [Switch] $SkipModules = $false,
        [Switch] $SkipLowStock = $false,
        [Switch] $SkipCategories = $false,
        [Switch] $SkipProducts = $false,
        [Switch] $SkipCmsPages = $false,
        [Switch] $SkipStoreConfig = $false,
        [Switch] $SkipCountries = $false,
        [Switch] $SkipCurrency = $false
    );
    # Start timer
    $sw = [Diagnostics.Stopwatch]::StartNew()

    $token = Get-MagentoToken -Url $Url -Username $Username -Password $Password;
    Write-Host "Using token: $token";
    # if there is not token
    if ($token -eq $null -or $token -eq "") {
        Write-Host "Token is null";
        return;
    }

    # Build basic summary object.
    $summary = @();

    # Add to urls to check
    $urlsToCheck = @($Url);
    $urlsToCheck += "$Url/checkout/cart";
    $urlsToCheck += "$Url/checkout";
    $urlsToCheck += "$Url/catalogsearch/result/?q=test";
    $urlsToCheck += "$Url/customer/account/login";
    $urlsToCheck += "$Url/customer/account/create";
    $urlsToCheck += "$Url/contact";
    $urlsToCheck += "$Url/contact-us";

    # Prepare request for API endpoints
    $params = @{
        Method = 'Get'
        Uri = "$Url"
        Body = @{}
        ContentType = "application/json; charset=utf-8"
        Authentication = "Bearer"
        Token = $token
        Headers = @{}
        AllowUnencryptedAuthentication = $true
    };

    # HTTP2 vs. HTTP1
    $response = Invoke-WebRequest -Uri $Url -Method Get -MaximumRedirection 1 -SkipHttpErrorCheck -HttpVersion 2 -ErrorAction SilentlyContinue -ErrorVariable err;
    $isHttp1 = $response.RawContent.Contains("HTTP/1.1");
    if ($isHttp1) {
        Write-Host "Site is using: HTTP/1.1";
    } else {
        Write-Host "Site is using: HTTP/2";
    }

    if ( $SkipCategories -eq $false ) {
        $categoryUrls = Get-MagentoCategories $Url $params;
        Write-Host "Found $($categoryUrls.length) categories";
        $urlsToCheck += $categoryUrls;
    }

    if ( $SkipProducts -eq $false ) {
        $productUrls = Get-MagentoProducts $Url $params;
        Write-Host "Found $($productUrls.length) products";
        $urlsToCheck += $productUrls;
    }

    if ( $SkipCmsPages -eq $false ) {
        $pagesUrls = Get-MagentoCmsPages -Url $Url -Params $params;
        Write-Host "Found $($pagesUrls.length) cms pages";
        $urlsToCheck += $pagesUrls;
    }

    if ( $SkipModules -eq $false ) {
        Get-MagentoModules $Url $params;
    }
    
    if ( $SkipStoreConfig -eq $false ) {
        $storeConfigs = Get-StoreConfig $Url $params;
        $storeConfigs | ForEach {[PSCustomObject]$_} | Format-Table ;
    }

    if ( $SkipCountries -eq $false ) {
        $countries = Get-AllowedCountires $Url $params;
        $countries | ForEach {[PSCustomObject]$_} | Format-Table -Property two_letter_abbreviation, three_letter_abbreviation, full_name_locale, full_name_english;
    }

    Write-Host "Checking $($urlsToCheck.length) urls";
    $summary = Get-MagentoUrlSummary $urlsToCheck $categoryUrls $productUrls $pagesUrls;

    $summary | ForEach {[PSCustomObject]$_} | Format-Table -AutoSize -Property url, type, status, error;

    Write-Host "Checked site: $Url";
    Write-Host "Total checked urls: $($urlsToCheck.length)";
    Write-Host "Total urls with errors: $($summary.length)";

    # Clear out and prepare other summary.
    $newSummary = @();

    if ( $SkipProducts -eq $false ) {
        $summaryCount = $($summary | Where-Object {$_.type -eq "product"} | Measure-Object).Count;
        $newSummary += @{
            type = "product";
            total = $($productUrls.length);
            error = $summaryCount;
            percent = $($summaryCount / $($productUrls.length) * 100 | Measure-Object -Average | Select-Object -ExpandProperty Average | ForEach-Object {"{0:N2}%" -f $_});
        };
    }

    if ( $SkipCategories -eq $false ) {
        $summaryCount = $($summary | Where-Object {$_.type -eq "category"} | Measure-Object).Count;
        $newSummary += @{
            type = "category";
            total = $($categoryUrls.length);
            error = $summaryCount;
            percent = $($summaryCount / $($categoryUrls.length) * 100 | Measure-Object -Average | Select-Object -ExpandProperty Average | ForEach-Object {"{0:N2}%" -f $_} );
        };
    }

    if ( $SkipCmsPages -eq $false ) {
        $summaryCount = $($summary | Where-Object {$_.type -eq "cms page"} | Measure-Object).Count;
        $newSummary += @{
            type = "cms page";
            total = $($pagesUrls.length);
            error = $summaryCount;
            percent = $($summaryCount / $($pagesUrls.length) * 100 | Measure-Object -Average | Select-Object -ExpandProperty Average | ForEach-Object {"{0:N2}%" -f $_});
        };
    }

    # Other urls with error
    $summaryCount = $($summary | Where-Object {$_.type -eq "other"} | Measure-Object).Count;
    $newSummary += @{
        type = "other";
        total = $($urlsToCheck.length) - $($productUrls.length) - $($categoryUrls.length) - $($pagesUrls.length);
        error = $summaryCount;
        percent = $($summaryCount / ($($urlsToCheck.length) - $($productUrls.length) - $($categoryUrls.length) - $($pagesUrls.length)) * 100 | Measure-Object -Average | Select-Object -ExpandProperty Average | ForEach-Object { "{0:N2}%" -f $_ });
    };

    # Print second table
    $newSummary | ForEach {[PSCustomObject]$_} | Format-Table -AutoSize -Property type, total, error, percent;

    if ( $SkipLowStock -eq $false ) {
        $lowStockProducts = Get-LowStockProducts -Url $Url $params;
    }

    # Stop timer
    $sw.Stop();
    Write-Host "Done in: $($sw.Elapsed)";
}

# Magento CMS Pages
function Get-MagentoCmsPages () {
    param (
        [String] $Url = "http://localhost",
        [Hashtable] $Params,
        [SecureString] $Token,
        [String] $Username = "dummy",
        [String] $Password = "Qwerty_2_Qwerty",
        [Int] $PageSize = 10,
        [Int] $Page = 1,
        [Switch] $Raw = $false
    );

    $token = $Token;
    if ( $token -eq $null ) {
        $token = Get-MagentoToken -Url $Url -Username $Username -Password $Password;
    }
    if ( $token -eq $null ) {
        Write-Host "Failed to generate token.";
        return $null;
    }

    $Params.Token = $token;

    $apiUrl = "$Url/rest/V1/cmsPage/search";
    $searchCriteria = @{searchCriteria=@{filterGroups=@{filters=@{field="is_active";value="1";conditionType="eq"}};sortOrders=@{field="title";direction="ASC"}};};

    $apiUrl = Format-MagentoSearchCriteria -Url $apiUrl -SearchCriteria $searchCriteria;
    $apiUrl = Add-MagentoPagination -Url $apiUrl -PageSize $PageSize -Page $Page;

    $Params.Uri = $apiUrl;
    $Params.Body = @{};
    
    $response = Invoke-RestMethod @Params;
    $pagesUrls = @();

    if ( $Raw ) {
        return $response;
    }

    $pages = $response.items;
    foreach ($item in $pages) {
        $pagesUrls += "$Url/$($item.identifier)";
        if( $pagesUrls.length -gt $global:cmsPageLimit ) {
            break;
        }
    }
    return $pagesUrls;
}
function Add-MagentoCmsPage () {
    param (
        [String] $Url = "http://localhost",
        [PSCustomObject] $page,
        [SecureString] $Token,
        [String] $Username = "dummy",
        [String] $Password = "Qwerty_2_Qwerty",
        [Switch] $Verbose = $false
    );

    if ( $page.page -eq $null ) {
        $page = @{
            "page" = $page;
        };
    }

    if ( $page.page.id -ne $null ) {
        $page.page.id = $null;
    }
    
    $token = $Token;
    if ( $token -eq $null ) {
        $token = Get-MagentoToken -Url $Url -Username $Username -Password $Password;
    }
    if ( $token -eq $null ) {
        Write-Host "Failed to generate token.";
        return $null;
    }

    $params = @{
        Method = 'Post'
        Uri = "$Url/rest/V1/cmsPage"
        Body = @{}
        ContentType = "application/json; charset=utf-8"
        Authentication = "Bearer"
        Token = $token
        Headers = @{}
        AllowUnencryptedAuthentication = $true
    };
    $params.Method = "Post";
    $params.Body = $( $page | ConvertTo-Json -Depth 10);
    $response = Invoke-RestMethod @params;
    if ( $Verbose ) {
        Write-Host "Added page: $($response.title ?? $response.identifier)";
        #Write-Host "Response: $($response | ConvertTo-Json -Depth 10)";
    }
    return $response;
}
function Find-MagentoCmsPage () {
    param (
        [String] $Url = "http://localhost",
        [String] $Identifier = "home",
        [SecureString] $Token,
        [String] $Username = "dummy",
        [String] $Password = "Qwerty_2_Qwerty"
    );

    $token = $Token;
    if ( $token -eq $null ) {
        $token = Get-MagentoToken -Url $Url -Username $Username -Password $Password;
    }
    if ( $token -eq $null ) {
        Write-Host "Failed to generate token.";
        return $null;
    }

    $params = @{
        Method = 'Get'
        Uri = "$Url/rest/V1/cmsPage/search"
        Body = @{}
        ContentType = "application/json; charset=utf-8"
        Authentication = "Bearer"
        Token = $token
        Headers = @{}
        AllowUnencryptedAuthentication = $true
    };
    $params.Method = "Get";
    $params.Body = @{searchCriteria=@{filterGroups=@{filters=@{field="identifier";value=$Identifier;conditionType="eq"}}}};
    $params.Uri = Format-MagentoSearchCriteria -Url $params.Uri -SearchCriteria $params.Body;
    $params.Body = @{};
    $response = Invoke-RestMethod @params;
    if ($response.items.length -gt 0) {
        return $response.items[0];
    }
    return $null;
}
function Copy-MagentoCmsPages () {
    param (
        [String] $SourceUrl = "http://localhost",
        [String] $SourceUsername = "dummy",
        [String] $SourcePassword = "Qwerty_2_Qwerty",
        [String] $DestinationUrl = "http://localhost",
        [String] $DestinationUsername = "dummy",
        [String] $DestinationPassword = "Qwerty_2_Qwerty",
        [Switch] $Verbose = $false
    );

    $pageCounter = 0;
    $sourceToken = Get-MagentoToken -Url $SourceUrl -Username $SourceUsername -Password $SourcePassword;
    $destinationToken = Get-MagentoToken -Url $DestinationUrl -Username $DestinationUsername -Password $DestinationPassword;
    $pageNumber = 1;

    $paramSource = @{
        Method = 'Get'
        Body = @{}
        ContentType = "application/json; charset=utf-8"
        Authentication = "Bearer"
        Headers = @{}
        AllowUnencryptedAuthentication = $true
    };

    $progressBar = $null;
    do {
        $sourceResponse = Get-MagentoCmsPages -Url $SourceUrl -Params $paramSource -Token $sourceToken -PageSize 10 -Page $pageNumber -Raw;
        $pages = $sourceResponse.items;
        if ($pages.length -eq 0) {
            break;
        }
        foreach($page in $pages) {
            $pageCheck = Find-MagentoCmsPage -Url $DestinationUrl -Identifier $page.identifier -Token $destinationToken;
            Write-Progress -Activity "Copying CMS pages" -Status "Copied $($pageCounter) pages out of $($sourceResponse.total_count)" -PercentComplete ($pageCounter / $sourceResponse.total_count * 100);
            if ( $pageCheck -ne $null) {
                if ( $Verbose ) {
                    Write-Host "Page already exists: $($page.title)";
                }
                $pageCounter += 1;
                continue;
            }
            $result = Add-MagentoCmsPage -Url $DestinationUrl -page $page -Token $destinationToken;
            $pageCounter += 1;
        }
        $pageNumber += 1;
    } while ($pageCounter -lt $sourceResponse.total_count);
}
#

# Magento CMS Blocks
function Get-MagentoCmsBlocks () {
    param (
        [String] $Url = "http://localhost",
        [Hashtable] $Params,
        [SecureString] $Token,
        [String] $Username = "dummy",
        [String] $Password = "Qwerty_2_Qwerty",
        [Int] $PageSize = 10,
        [Int] $Page = 1
    );

    $token = $Token;
    if ( $token -eq $null ) {
        $token = Get-MagentoToken -Url $Url -Username $Username -Password $Password;
    }
    if ( $token -eq $null ) {
        Write-Host "Failed to generate token.";
        return $null;
    }

    $Params.Token = $token;

    $apiUrl = "$Url/rest/V1/cmsBlock/search";
    $searchCriteria = @{searchCriteria=@{filterGroups=@{filters=@{field="is_active";value="1";conditionType="eq"}};sortOrders=@{field="title";direction="ASC"}};};

    $apiUrl = Format-MagentoSearchCriteria -Url $apiUrl -SearchCriteria $searchCriteria;
    $apiUrl = Add-MagentoPagination -Url $apiUrl -PageSize $PageSize -Page $Page;

    $Params.Uri = $apiUrl;
    $Params.Body = @{};
    
    $response = Invoke-RestMethod @Params;
    return $response;
}
function Add-MagentoCmsBlock () {
    param (
        [String] $Url = "http://localhost",
        [PSCustomObject] $Block,
        [SecureString] $Token,
        [String] $Username = "dummy",
        [String] $Password = "Qwerty_2_Qwerty",
        [Switch] $Verbose = $false
    );

    if ( $Block.block -eq $null ) {
        $Block = @{
            "block" = $Block;
        };
    }

    if ( $Block.block.id -ne $null ) {
        $Block.block.id = $null;
    }
    
    $token = $Token;
    if ( $token -eq $null ) {
        $token = Get-MagentoToken -Url $Url -Username $Username -Password $Password;
    }
    if ( $token -eq $null ) {
        Write-Host "Failed to generate token.";
        return $null;
    }

    $params = @{
        Method = 'Post'
        Uri = "$Url/rest/V1/cmsBlock"
        Body = @{}
        ContentType = "application/json; charset=utf-8"
        Authentication = "Bearer"
        Token = $token
        Headers = @{}
        AllowUnencryptedAuthentication = $true
    };
    $params.Method = "Post";
    $params.Body = $( $Block | ConvertTo-Json -Depth 10);
    $response = Invoke-RestMethod @params;
    if ( $Verbose ) {
        Write-Host "Added block: $($response.title ?? $response.identifier)";
        #Write-Host "Response: $($response | ConvertTo-Json -Depth 10)";
    }
    return $response;
}
function Find-MagentoCmsBlock () {
    param (
        [String] $Url = "http://localhost",
        [String] $Identifier = "home",
        [SecureString] $Token,
        [String] $Username = "dummy",
        [String] $Password = "Qwerty_2_Qwerty"
    );

    $token = $Token;
    if ( $token -eq $null ) {
        $token = Get-MagentoToken -Url $Url -Username $Username -Password $Password;
    }
    if ( $token -eq $null ) {
        Write-Host "Failed to generate token.";
        return $null;
    }

    $params = @{
        Method = 'Get'
        Uri = "$Url/rest/V1/cmsBlock/search"
        Body = @{}
        ContentType = "application/json; charset=utf-8"
        Authentication = "Bearer"
        Token = $token
        Headers = @{}
        AllowUnencryptedAuthentication = $true
    };
    $params.Method = "Get";
    $params.Body = @{searchCriteria=@{filterGroups=@{filters=@{field="identifier";value=$Identifier;conditionType="eq"}}}};
    $params.Uri = Format-MagentoSearchCriteria -Url $params.Uri -SearchCriteria $params.Body;
    $params.Body = @{};
    $response = Invoke-RestMethod @params;
    if ($response.items.length -gt 0) {
        return $response.items[0];
    }
    return $null;
}
function Copy-MagentoCmsBlocks () {
    param (
        [String] $SourceUrl = "http://localhost",
        [String] $SourceUsername = "dummy",
        [String] $SourcePassword = "Qwerty_2_Qwerty",
        [String] $DestinationUrl = "http://localhost",
        [String] $DestinationUsername = "dummy",
        [String] $DestinationPassword = "Qwerty_2_Qwerty",
        [Switch] $Verbose = $false
    );

    $blockNumber = 0;
    $sourceToken = Get-MagentoToken -Url $SourceUrl -Username $SourceUsername -Password $SourcePassword;
    $destinationToken = Get-MagentoToken -Url $DestinationUrl -Username $DestinationUsername -Password $DestinationPassword;
    $pageNumber = 1;

    $paramSource = @{
        Method = 'Get'
        Body = @{}
        ContentType = "application/json; charset=utf-8"
        Authentication = "Bearer"
        Headers = @{}
        AllowUnencryptedAuthentication = $true
    };

    $progressBar = $null;
    do {
        $sourceResponse = Get-MagentoCmsBlocks -Url $SourceUrl -Params $paramSource -Token $sourceToken -PageSize 10 -Page $pageNumber -Raw;
        $blocks = $sourceResponse.items;
        if ($blocks.length -eq 0) {
            break;
        }
        foreach($Block in $blocks) {
            $pageCheck = Find-MagentoCmsBlock -Url $DestinationUrl -Identifier $Block.identifier -Token $destinationToken;
            Write-Progress -Activity "Copying CMS blocks" -Status "Copied $($blockNumber) blocks out of $($sourceResponse.total_count)" -PercentComplete ($blockNumber / $sourceResponse.total_count * 100);
            if ( $pageCheck -ne $null) {
                if ( $Verbose ) {
                    Write-Host "Block already exists: $($Block.title)";
                }
                $blockNumber += 1;
                continue;
            }
            $result = Add-MagentoCmsBlock -Url $DestinationUrl -Block $Block -Token $destinationToken;
            $blockNumber += 1;
        }
        $pageNumber += 1;
    } while ($blockNumber -lt $sourceResponse.total_count);
}
#

function Copy-MagentoCmsContent () {
     param (
        [String] $SourceUrl = "http://localhost",
        [String] $SourceUsername = "dummy",
        [String] $SourcePassword = "Qwerty_2_Qwerty",
        [String] $DestinationUrl = "http://localhost",
        [String] $DestinationUsername = "dummy",
        [String] $DestinationPassword = "Qwerty_2_Qwerty",
        [Switch] $Verbose = $false
    );

    Copy-MagentoCmsPages -SourceUrl $SourceUrl -SourceUsername $SourceUsername -SourcePassword $SourcePassword -DestinationUrl $DestinationUrl -DestinationUsername $DestinationUsername -DestinationPassword $DestinationPassword -Verbose $Verbose;
    Copy-MagentoCmsBlocks -SourceUrl $SourceUrl -SourceUsername $SourceUsername -SourcePassword $SourcePassword -DestinationUrl $DestinationUrl -DestinationUsername $DestinationUsername -DestinationPassword $DestinationPassword -Verbose $Verbose;
}

function Install-Magento () {
    param (
        [String] $MagentoPath = "C:\Users\user\Documents\GitHub\magento2"
    );
    Install-Script -Name install-qemu-img;
    #check for arch iso
    $isoPath = "C:\Users\user\Downloads\archlinux-2020.12.01-x86_64.iso";
    if (Test-Path $isoPath) {
        Write-Host "Found iso file: $isoPath";
    } else {
        Write-Host "Iso file not found: $isoPath";
        return;
    }
    #https://unix.stackexchange.com/a/525120
    qemu-img create \
            -f qcow2 archlinux.qcow2 20G \
            -netdev user,id=mynet0,net=192.168.76.0/24,dhcpstart=192.168.76.9 \ #-netdev user,id=n0 -device rtl8139,netdev=n0
            -device virtio-net-pci,netdev=mynet0 \
            -cdrom $isoPath \
            -boot d \
            -m 2048 \
            -smp 2;
}

if( $args[0] -eq "help" ) {
    Write-Host "Usage: status.ps1 <url> <username> <password>";
    Write-Host "Example: status.ps1 http://localhost dummy Qwerty_2_Qwerty";
    exit;
} elseif( $args.length -gt 0 ) {
    Check-MagentoUrls;
}