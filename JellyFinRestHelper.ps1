function get-JFItems
{
    Param([Parameter(Mandatory)]
    [ValidateSet("Movie","Audio","Folder","MusicAlbum","MusicArtist","BoxSet", "Video", "Episode")]
    $type,
    [Parameter(Mandatory)]
    $authInfo)

    $headers = @{}
    $headers["X-MediaBrowser-Token"] = $authInfo.ApiKey  # this is not documented.  lol.
    $returnObj = @() 
    switch($type)
    {
        "Movie" {$viewName = "Movies"}
        "MusicAlbum" {$viewName = "Music"}
        "Video" {$viewName = "Shows"}
    }
   
    $ViewId = get-JFViewId -viewName $viewName -authInfo $authInfo
    #ParentId=$ViewId
    $col = Invoke-RestMethod -Uri "$($authInfo.Uri)/Items?IncludeItemTypes=$type&Recursive=true"  -Method Get -UseBasicParsing -Headers $headers 
        
    foreach($colitem in $col.Items)
    {
        $ItemObj = (Invoke-WebRequest -Uri "$($authInfo.Uri)/Items/$($colitem.Id)" -Headers $headers -UseBasicParsing -Method Get).Content | convertfrom-json 
        $returnObj += $ItemObj 
    }    
    return $returnObj
}

# Is this actually needed if we get HTTP 204 for every successful ADD operation (even a noop)?
function get-JFCollectionItems
{
    Param([Parameter(Mandatory)]
    [ValidateSet("Movie","Audio","Folder","MusicAlbum","MusicArtist","BoxSet", "Video", "Episode")]
    $type,
    [Parameter(Mandatory)]
    $authInfo,
    $collectionName)

    $headers = @{}
    $headers["X-MediaBrowser-Token"] = $authInfo.ApiKey  # this is not documented.  lol.
    $returnObj = @() 
    switch($type)
    {
        "Movie" {$viewName = "Movies"}
        "MusicAlbum" {$viewName = "Music"}
        "Video" {$viewName = "Shows"}
    }
   
    $ViewId = get-JFViewId -viewName $viewName -authInfo $authInfo
    $col = Invoke-RestMethod -Uri "$($authInfo.Uri)/Items?IncludeItemTypes=$type&Recursive=true"  -Method Get -UseBasicParsing -Headers $headers 
        
    foreach($colitem in $col.Items)
    {
        $ItemObj = (Invoke-WebRequest -Uri "$($authInfo.Uri)/Items/$($colitem.Id)" -Headers $headers -UseBasicParsing -Method Get).Content | convertfrom-json 
        $returnObj += $ItemObj 
    }    
    return $returnObj
}

function add-JFItemToCollection{
    Param([Parameter(Mandatory)]
    $itemid, 
    [Parameter(Mandatory)]
    $collectionName,
    [Parameter(Mandatory)]
    $authInfo)

    $headers = @{}
    $headers["X-MediaBrowser-Token"] = $authInfo.ApiKey  # this is not documented.  lol.
    $collectionID = get-JFcollectionId -collectionName $collectionName -authInfo $authInfo
    Invoke-WebRequest -Uri "$($authInfo.Uri.Split("Users")[0])Collections/$collectionId/Items?Ids=$itemid" -Headers $headers -UseBasicParsing -Method "POST"
}

function get-JFcollectionId
{
    Param(
    [Parameter(Mandatory)]
    $collectionName,
    [Parameter(Mandatory)]
    $authInfo)

    $headers = @{}
    $headers["X-MediaBrowser-Token"] = $authInfo.ApiKey  # this is not documented.  lol.

    $viewId = Get-JFViewId -viewName "Collections" -authInfo $authInfo
    $collections = Invoke-RestMethod -Uri "$($authInfo.Uri)/Items?Fields=SortName%2CPath&ParentId=$viewId" -Method Get -Headers $headers

    foreach($collection in $collections.Items)
    {
        if($collection.Name -eq $collectionName)
        {
            return $collection.Id
        }
    }
    throw "No Matching Collection ID!"
}

function get-JFViewId
{
    Param(
    [Parameter(Mandatory)]
    $viewName,
    [Parameter(Mandatory)]
    $authInfo)

    $headers = @{}
    $headers["X-MediaBrowser-Token"] = $authInfo.ApiKey  # this is not documented.  lol.
    $response = Invoke-RestMethod -Uri "$($authInfo.Uri)/Views" -Method Get -Headers $headers
    foreach($view in $response.Items)
    {
        if($view.Name -eq $viewName)
        {
            return $view.Id
        }
    }    
    throw "No matching view found!"
}

<# The AuthInfo object is expected to be like:
$authInfo = [PSCustomObject]@{
    ApiKey     = "apikey"
    UserId = "userid"
    Uri    = "http://192.168.2.155:8096/Users/(userid)"
}
#>
