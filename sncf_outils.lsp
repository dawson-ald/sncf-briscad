(vl-load-com)
(setq *SCRIPT_ID* "SNCF_Outils")
(setq *S_SCRIPT_VERSION* "0.2")
(princ (strcat "\nInformation: Script Outils SNCF développé par Dawson AILLAUD - SNCF Réseau TL MOB - Version " *S_SCRIPT_VERSION*))

;; ------------------------------------------------------------------------------------ F_MAJ ------------------------------------------------------------------------------------

(defun SMAJ:read-file (path / f line txt)
  (setq txt "")
  (if (setq f (open path "r"))
    (progn
      (while (setq line (read-line f))
        (setq txt (strcat txt line "\n"))
      )
      (close f)
      txt
    )
    nil
  )
)

(defun SMAJ:replace-all (s old new / p)
  (while (setq p (vl-string-search old s))
    (setq s
      (strcat
        (substr s 1 p)
        new
        (substr s (+ p (strlen old) 1))
      )
    )
  )
  s
)

(defun SMAJ:normalize-path (p)
  (if p
    (progn
      (setq p (vl-string-trim " \t\r\n\"'" p))
      (setq p (SMAJ:replace-all p "\\\\" "\\"))
      (setq p (SMAJ:replace-all p "/" "\\"))
      (while (vl-string-search "\\\\" p)
        (setq p (SMAJ:replace-all p "\\\\" "\\"))
      )
      p
    )
  )
)

(defun SMAJ:add-unique (x lst)
  (if (member x lst)
    lst
    (cons x lst)
  )
)

(defun SMAJ:get-subdirs (folder / fso fld sub result)
  (setq result '())

  (if (and folder (vl-file-directory-p folder))
    (progn
      (setq fso (vlax-create-object "Scripting.FileSystemObject"))
      (setq fld (vlax-invoke-method fso 'GetFolder folder))

      (vlax-for sub (vlax-get-property fld 'SubFolders)
        (setq result
          (cons
            (vlax-get-property sub 'Path)
            result
          )
        )
      )

      (vlax-release-object fld)
      (vlax-release-object fso)
    )
  )

  (reverse result)
)

(defun SMAJ:find-appload-dfs (/ appdata base versions langs v l p found)
  (setq found '())
  (setq appdata (getenv "APPDATA"))

  (if appdata
    (progn
      (setq base (strcat appdata "\\Bricsys\\BricsCAD"))

      (if (vl-file-directory-p base)
        (progn
          (setq versions (SMAJ:get-subdirs base))

          (foreach v versions
            (setq langs (SMAJ:get-subdirs v))

            (foreach l langs
              (setq p (strcat l "\\appload.dfs"))

              (if (findfile p)
                (setq found (SMAJ:add-unique p found))
              )
            )
          )
        )
      )
    )
  )

  (reverse found)
)

(defun SMAJ:make-ps-list (lst / s x)
  (setq s "@(")

  (foreach x lst
    (setq x (SMAJ:replace-all x "'" "''"))
    (setq s (strcat s "'" x "',"))
  )

  (if (= (substr s (strlen s) 1) ",")
    (setq s (substr s 1 (1- (strlen s))))
  )

  (setq s (strcat s ")"))
  s
)

(defun SMAJ:run-powershell-update (dfsFiles resultFile / psFile ps f shell rc dfsList)
  (setq psFile (strcat (getenv "TEMP") "\\sncf_maj_update.ps1"))
  (setq dfsList (SMAJ:make-ps-list dfsFiles))

  (if (findfile psFile)
    (vl-file-delete psFile)
  )

  (if (findfile resultFile)
    (vl-file-delete resultFile)
  )

  (setq ps
    (strcat
      "$ErrorActionPreference = 'Stop'\n"
      "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12\n"

      "$owner = 'dawson-ald'\n"
      "$repo = 'sncf-briscad'\n"
      "$filePath = 'sncf_outils.lsp'\n"
      "$branch = 'main'\n"

      "$resultFile = '" (SMAJ:replace-all resultFile "'" "''") "'\n"
      "$dfsFiles = " dfsList "\n"

      "function Read-TextAny($p) {\n"
      "  try { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) } catch {}\n"
      "  try { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::Default) } catch {}\n"
      "  try { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::Unicode) } catch {}\n"
      "  return ''\n"
      "}\n"

      "function Is-SncfScript($txt) {\n"
      "  if ([string]::IsNullOrWhiteSpace($txt)) { return $false }\n"
      "  $clean = $txt.ToUpper() -replace '\\s+', ''\n"
      "  return ($clean.Contains('*SCRIPT_ID*') -and $clean.Contains('SNCF_OUTILS'))\n"
      "}\n"

      "function Normalize-PathText($p) {\n"
      "  if ($null -eq $p) { return $null }\n"
      "  $p = $p.Trim()\n"
      "  $p = $p.Trim([char]34, [char]39)\n"
      "  $p = $p -replace '/', '\\'\n"
      "  $p = $p -replace '\\\\', '\\'\n"
      "  while ($p -match '\\\\\\\\') { $p = $p -replace '\\\\', '\\' }\n"
      "  return $p\n"
      "}\n"

      "function Extract-ScriptPaths($txt) {\n"
      "  $items = New-Object System.Collections.Generic.List[string]\n"
      "  if ([string]::IsNullOrWhiteSpace($txt)) { return $items }\n"

      "  $patterns = @(\n"
      "    '[A-Za-z]:\\\\(?:[^<>:\"\"\\r\\n\\|\\?\\*]+?)\\.(?:lsp|fas|vlx)',\n"
      "    '[A-Za-z]:\\\\\\\\(?:[^<>:\"\"\\r\\n\\|\\?\\*]+?)\\.(?:lsp|fas|vlx)'\n"
      "  )\n"

      "  foreach ($pat in $patterns) {\n"
      "    $matches = [regex]::Matches($txt, $pat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)\n"
      "    foreach ($m in $matches) {\n"
      "      $p = Normalize-PathText $m.Value\n"
      "      if ($p -and -not $items.Contains($p)) { $items.Add($p) }\n"
      "    }\n"
      "  }\n"

      "  return $items\n"
      "}\n"

      "function New-WebClientNoCache() {\n"
      "  $wc = New-Object System.Net.WebClient\n"
      "  $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()\n"
      "  $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials\n"
      "  $wc.Headers.Add('User-Agent','Mozilla/5.0 SNCF-MAJ')\n"
      "  $wc.Headers.Add('Accept','application/vnd.github+json')\n"
      "  $wc.Headers.Add('Cache-Control','no-cache, no-store, must-revalidate')\n"
      "  $wc.Headers.Add('Pragma','no-cache')\n"
      "  $wc.Headers.Add('Expires','0')\n"
      "  return $wc\n"
      "}\n"

      "function Get-GitHubLatestContent() {\n"
      "  $nonce = [Guid]::NewGuid().ToString()\n"
      "  $branchUrl = \"https://api.github.com/repos/$owner/$repo/branches/$branch`?nocache=$nonce\"\n"

      "  $wc1 = New-WebClientNoCache\n"
      "  $branchJson = $wc1.DownloadString($branchUrl)\n"
      "  $branchObj = $branchJson | ConvertFrom-Json\n"
      "  $sha = $branchObj.commit.sha\n"

      "  if ([string]::IsNullOrWhiteSpace($sha)) {\n"
      "    throw 'Impossible de recuperer le dernier SHA GitHub.'\n"
      "  }\n"

      "  $nonce2 = [Guid]::NewGuid().ToString()\n"
      "  $contentUrl = \"https://api.github.com/repos/$owner/$repo/contents/$filePath`?ref=$sha&nocache=$nonce2\"\n"

      "  $wc2 = New-WebClientNoCache\n"
      "  $contentJson = $wc2.DownloadString($contentUrl)\n"
      "  $contentObj = $contentJson | ConvertFrom-Json\n"

      "  if ([string]::IsNullOrWhiteSpace($contentObj.content)) {\n"
      "    throw 'Contenu GitHub vide ou introuvable.'\n"
      "  }\n"

      "  $base64 = ($contentObj.content -replace '\\s+', '')\n"
      "  $bytes = [Convert]::FromBase64String($base64)\n"
      "  $txt = [System.Text.Encoding]::UTF8.GetString($bytes)\n"

      "  return $txt\n"
      "}\n"

      "$newTxt = Get-GitHubLatestContent\n"

      "if (!(Is-SncfScript $newTxt)) {\n"
      "  throw 'Le fichier telecharge ne contient pas *SCRIPT_ID* SNCF_Outils.'\n"
      "}\n"

      "$allPaths = New-Object System.Collections.Generic.List[string]\n"

      "foreach ($dfs in $dfsFiles) {\n"
      "  if (!(Test-Path -LiteralPath $dfs)) { continue }\n"

      "  $dfsTxt = Read-TextAny $dfs\n"
      "  $paths = Extract-ScriptPaths $dfsTxt\n"

      "  foreach ($p in $paths) {\n"
      "    if (-not $allPaths.Contains($p)) {\n"
      "      $allPaths.Add($p)\n"
      "    }\n"
      "  }\n"
      "}\n"

      "$updated = New-Object System.Collections.Generic.List[string]\n"

      "foreach ($p in $allPaths) {\n"
      "  if (!(Test-Path -LiteralPath $p)) { continue }\n"

      "  $oldTxt = Read-TextAny $p\n"

      "  if (Is-SncfScript $oldTxt) {\n"
      "    [System.IO.File]::WriteAllText($p, $newTxt, [System.Text.Encoding]::UTF8)\n"

      "    if (-not $updated.Contains($p)) {\n"
      "      $updated.Add($p)\n"
      "    }\n"
      "  }\n"
      "}\n"

      "if ($updated.Count -gt 0) {\n"
      "  Set-Content -LiteralPath $resultFile -Value $updated -Encoding UTF8\n"
      "} else {\n"
      "  Set-Content -LiteralPath $resultFile -Value '' -Encoding UTF8\n"
      "}\n"
    )
  )

  (if (setq f (open psFile "w"))
    (progn
      (write-line ps f)
      (close f)

      (setq shell (vlax-create-object "WScript.Shell"))

      (setq rc
        (vlax-invoke-method
          shell
          'Run
          (strcat
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -File "
            "\""
            psFile
            "\""
          )
          0
          :vlax-true
        )
      )

      (vlax-release-object shell)

      rc
    )
    -1
  )
)

(defun SMAJ:read-lines-as-list (path / f line lst p)
  (setq lst '())

  (if (setq f (open path "r"))
    (progn
      (while (setq line (read-line f))
        (setq p (SMAJ:normalize-path line))

        (if (and p (/= p ""))
          (setq lst (cons p lst))
        )
      )

      (close f)
    )
  )

  (reverse lst)
)

(defun C:S_MAJ (/ dfsFiles resultFile rc updated p nb)
  (setq dfsFiles (SMAJ:find-appload-dfs))
  (setq resultFile (strcat (getenv "TEMP") "\\sncf_maj_updated.txt"))

  (if (not dfsFiles)
    (progn
      (princ "\nAucun fichier appload.dfs trouve.")
      (princ "\nRecherche faite dans : %APPDATA%\\Bricsys\\BricsCAD\\")
    )
    (progn
      (princ "\nMise a jour en cours...")

      (setq rc (SMAJ:run-powershell-update dfsFiles resultFile))

      (if (/= rc 0)
        (progn
          (princ "\nErreur pendant la mise a jour.")
          (princ (strcat "\nCode retour : " (itoa rc)))
        )
        (progn
          (setq updated (SMAJ:read-lines-as-list resultFile))
          (setq nb 0)

          (foreach p updated
            (if (findfile p)
              (progn
                (setq nb (1+ nb))
                (load p)
              )
            )
          )

          (if (> nb 0)
            (princ
                "\nMise a jour terminee ! "
            )
            (princ "\nAucun script mis a jour.")
          )
        )
      )
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ F_UTILS ------------------------------------------------------------------------------------

(defun make-layer (name color /)
  (if (not (tblsearch "LAYER" name))
    (command "_.LAYER" "_N" name "_C" color name "")
  )
)

(defun draw-poly4 (p1 p2 p3 p4 layer / data ent)
  (vl-load-com)

  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Vérifier les points
  (if (or (null p1) (null p2) (null p3) (null p4))
    (progn
      (princ "\nErreur : points invalides pour le polygone.")
      nil
    )
    (progn
      ;; Polyligne fermée à 4 sommets
      (setq data
        (list
          (cons 0 "LWPOLYLINE")
          (cons 100 "AcDbEntity")
          (cons 8 layer)
          (cons 100 "AcDbPolyline")
          (cons 90 4)
          (cons 70 1)

          (cons 10 (list (car p1) (cadr p1)))
          (cons 10 (list (car p2) (cadr p2)))
          (cons 10 (list (car p3) (cadr p3)))
          (cons 10 (list (car p4) (cadr p4)))
        )
      )

      (setq ent (entmake data))
      ent
    )
  )
)

(defun hatch-poly4-color (p1 p2 p3 p4 layer color / data ent)
  (vl-load-com)

  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Vérifier les points
  (if (or (null p1) (null p2) (null p3) (null p4))
    (progn
      (princ "\nErreur : points invalides pour la hachure.")
      nil
    )
    (progn
      ;; Hachure SOLID avec contour à 4 lignes
      (setq data
        (list
          (cons 0 "HATCH")
          (cons 100 "AcDbEntity")
          (cons 8 layer)
          (cons 62 color)
          (cons 100 "AcDbHatch")
          (cons 10 (list 0.0 0.0 0.0))
          (cons 210 (list 0.0 0.0 1.0))
          (cons 2 "SOLID")
          (cons 70 1)
          (cons 71 0)
          (cons 91 1)

          ;; Boucle extérieure
          (cons 92 1)
          (cons 93 4)

          ;; p1 -> p2
          (cons 72 1)
          (cons 10 (list (car p1) (cadr p1)))
          (cons 11 (list (car p2) (cadr p2)))

          ;; p2 -> p3
          (cons 72 1)
          (cons 10 (list (car p2) (cadr p2)))
          (cons 11 (list (car p3) (cadr p3)))

          ;; p3 -> p4
          (cons 72 1)
          (cons 10 (list (car p3) (cadr p3)))
          (cons 11 (list (car p4) (cadr p4)))

          ;; p4 -> p1
          (cons 72 1)
          (cons 10 (list (car p4) (cadr p4)))
          (cons 11 (list (car p1) (cadr p1)))

          (cons 97 0)
          (cons 75 0)
          (cons 76 1)
          (cons 47 1.0)
          (cons 98 0)
        )
      )

      ;; entmakex retourne bien le nom de l'entité
      (setq ent (entmakex data))

      ;; Envoyer la hachure à l'arrière
      (if ent
        (command "_.DRAWORDER" ent "" "_B")
      )

      ent
    )
  )
)

(defun hatch-poly4-pattern (p1 p2 p3 p4 layer color pattern scale / data ent isSolid)
  (vl-load-com)

  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Valeurs par défaut
  (if (or (null pattern) (= pattern ""))
    (setq pattern "ANSI31")
  )

  (if (null scale)
    (setq scale 1.0)
  )

  (setq isSolid (= (strcase pattern) "SOLID"))

  ;; Vérifier les points
  (if (or (null p1) (null p2) (null p3) (null p4))
    (progn
      (princ "\nErreur : points invalides pour la hachure.")
      nil
    )
    (progn
      (setq data
        (list
          (cons 0 "HATCH")
          (cons 100 "AcDbEntity")
          (cons 8 layer)
          (cons 62 color)
          (cons 100 "AcDbHatch")
          (cons 10 (list 0.0 0.0 0.0))
          (cons 210 (list 0.0 0.0 1.0))

          ;; Motif choisi
          (cons 2 pattern)

          ;; 1 = solid, 0 = motif
          (cons 70 (if isSolid 1 0))
          (cons 71 0)
          (cons 91 1)

          ;; Boucle extérieure
          (cons 92 1)
          (cons 93 4)

          ;; p1 -> p2
          (cons 72 1)
          (cons 10 (list (car p1) (cadr p1)))
          (cons 11 (list (car p2) (cadr p2)))

          ;; p2 -> p3
          (cons 72 1)
          (cons 10 (list (car p2) (cadr p2)))
          (cons 11 (list (car p3) (cadr p3)))

          ;; p3 -> p4
          (cons 72 1)
          (cons 10 (list (car p3) (cadr p3)))
          (cons 11 (list (car p4) (cadr p4)))

          ;; p4 -> p1
          (cons 72 1)
          (cons 10 (list (car p4) (cadr p4)))
          (cons 11 (list (car p1) (cadr p1)))

          (cons 97 0)
          (cons 75 0)
          (cons 76 1)

          ;; Angle et échelle
          (cons 52 0.0)
          (cons 41 scale)

          (cons 77 0)
          (cons 78 0)
          (cons 47 1.0)
          (cons 98 0)
        )
      )

      (setq ent (entmakex data))

      ;; Envoyer la hachure à l'arrière
      (if ent
        (command "_.DRAWORDER" ent "" "_B")
      )

      ent
    )
  )
)

(defun draw-text (pt texte layer taille rotation /)
  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Créer le texte directement, sans commande AutoCAD/BricsCAD
  (entmake
    (list
      (cons 0 "TEXT")
      (cons 8 layer)
      (cons 10 pt)          ;; point d'insertion
      (cons 11 pt)          ;; point d'alignement
      (cons 40 taille)      ;; hauteur du texte
      (cons 1 texte)        ;; contenu du texte
      (cons 50 rotation)    ;; rotation en radians
      (cons 7 "Standard")   ;; style de texte
      (cons 72 1)           ;; justification horizontale : centre
      (cons 73 2)           ;; justification verticale : milieu
    )
  )
)

(defun mtext-convert-newlines (txt / i n ch next res)
  (setq i 1)
  (setq n (strlen txt))
  (setq res "")

  (while (<= i n)
    (setq ch (substr txt i 1))

    (if (= ch "\\")
      (progn
        (setq next (if (< i n) (substr txt (+ i 1) 1) ""))

        ;; Si c'est deja \P, on le garde comme retour ligne MTEXT
        (if (or (= next "P") (= next "p"))
          (progn
            (setq res (strcat res "\\P"))
            (setq i (+ i 2))
          )
          ;; Sinon, un simple \ devient \P
          (progn
            (setq res (strcat res "\\P"))
            (setq i (+ i 1))
          )
        )
      )
      (progn
        (setq res (strcat res ch))
        (setq i (+ i 1))
      )
    )
  )

  res
)

(defun draw-mtext (pt texte layer taille rotation largeur /)
  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Convertir les \ en retours ligne MTEXT \P
  (setq texte (mtext-convert-newlines texte))

  ;; Créer un MTEXT avec retour à la ligne
  (entmake
    (list
      (cons 0 "MTEXT")
      (cons 100 "AcDbEntity")
      (cons 8 layer)
      (cons 100 "AcDbMText")
      (cons 10 pt)
      (cons 40 taille)
      (cons 41 largeur)
      (cons 1 texte)
      (cons 50 rotation)
      (cons 7 "Standard")
      (cons 71 5)
    )
  )
)

(defun draw-line (p1 p2 layer ltype ltscale / data ent)
  (vl-load-com)

  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Si le type de ligne n'existe pas, utiliser Continuous
  (if (or (null ltype) (not (tblsearch "LTYPE" ltype)))
    (setq ltype "Continuous")
  )

  ;; Sécurité : vérifier que les deux points sont différents
  (if (equal p1 p2 0.000001)
    (progn
      (princ "\nErreur : ligne non creee car les deux points sont identiques.")
      nil
    )
    (progn
      ;; Création directe de la ligne
      (setq data
        (list
          (cons 0 "LINE")
          (cons 8 layer)
          (cons 10 p1)
          (cons 11 p2)
          (cons 6 ltype)
          (cons 48 ltscale)
        )
      )

      (setq ent (entmake data))
      ent
    )
  )
)

(defun draw-line-ep (p1 p2 layer ltype ltscale epaisseur / data ent lw)
  (vl-load-com)

  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Si le type de ligne n'existe pas, utiliser Continuous
  (if (or (null ltype) (not (tblsearch "LTYPE" ltype)))
    (setq ltype "Continuous")
  )

  ;; Echelle type de ligne par defaut
  (if (null ltscale)
    (setq ltscale 1.0)
  )

  ;; Epaisseur de ligne
  ;; DXF 370 = epaisseur en centiemes de mm
  ;; Exemple : 0.25 mm -> 25
  ;; -1 = ByLayer
  (if (or (null epaisseur) (<= epaisseur 0))
    (setq lw -1)
    (setq lw (fix (* epaisseur 100.0)))
  )

  ;; Sécurité : vérifier que les deux points sont différents
  (if (equal p1 p2 0.000001)
    (progn
      (princ "\nErreur : ligne non creee car les deux points sont identiques.")
      nil
    )
    (progn
      ;; Création directe de la ligne
      (setq data
        (list
          (cons 0 "LINE")
          (cons 8 layer)
          (cons 10 p1)
          (cons 11 p2)
          (cons 6 ltype)
          (cons 48 ltscale)
          (cons 370 lw)
        )
      )

      (setq ent (entmake data))
      ent
    )
  )
)

(defun draw-line-color (p1 p2 layer ltype ltscale color / data ent)
  (vl-load-com)

  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Si le type de ligne n'existe pas, utiliser Continuous
  (if (or (null ltype) (not (tblsearch "LTYPE" ltype)))
    (setq ltype "Continuous")
  )

  ;; Sécurité : vérifier que les deux points sont différents
  (if (equal p1 p2 0.000001)
    (progn
      (princ "\nErreur : ligne non creee car les deux points sont identiques.")
      nil
    )
    (progn
      (setq data
        (list
          (cons 0 "LINE")
          (cons 8 layer)
          (cons 10 p1)
          (cons 11 p2)
          (cons 6 ltype)
          (cons 48 ltscale)
          (cons 62 color) ;; Couleur AutoCAD/BricsCAD
        )
      )

      (setq ent (entmake data))
      ent
    )
  )
)

(defun draw-rect (p1 p2 layer / x1 y1 x2 y2 data ent)
  (vl-load-com)

  ;; Créer le calque si besoin
  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  ;; Vérifier les points
  (if (or (null p1) (null p2))
    (progn
      (princ "\nErreur : points invalides pour le rectangle.")
      nil
    )
    (progn
      (setq x1 (car p1))
      (setq y1 (cadr p1))
      (setq x2 (car p2))
      (setq y2 (cadr p2))

      (if (or (null x1) (null y1) (null x2) (null y2))
        (progn
          (princ "\nErreur : coordonnees invalides pour le rectangle.")
          nil
        )
        (progn
          ;; Polyligne fermee
          (setq data
            (list
              (cons 0 "LWPOLYLINE")
              (cons 100 "AcDbEntity")
              (cons 8 layer)
              (cons 100 "AcDbPolyline")
              (cons 90 4)
              (cons 70 1)

              ;; Sommets du rectangle
              (cons 10 (list x1 y1))
              (cons 10 (list x2 y1))
              (cons 10 (list x2 y2))
              (cons 10 (list x1 y2))
            )
          )

          (setq ent (entmake data))
          ent
        )
      )
    )
  )
)
(defun pt-2d (p)
  (list (car p) (cadr p) 0.0)
)

(defun draw-cotlin-perso (p1 p2 texte layer / pos decalage oldos oldlay dx dy sens dist)
  ;; p1 = premier point mesure
  ;; p2 = deuxieme point mesure
  ;; texte = texte affiche dans la cotation
  ;; layer = calque de la cotation
  ;; sens = "H" ou "V" determine automatiquement

  (setq p1 (pt-2d p1))
  (setq p2 (pt-2d p2))

  ;; Ecart horizontal / vertical
  (setq dx (abs (- (car p2) (car p1))))
  (setq dy (abs (- (cadr p2) (cadr p1))))

  ;; Choix automatique du sens
  (setq sens
    (if (>= dx dy)
      "H"
      "V"
    )
  )

  ;; Texte automatique selon le sens de cote
  (if (or (null texte) (= texte ""))
    (progn
      (setq dist
        (if (= sens "H")
          dx
          dy
        )
      )
      (setq texte (strcat (rtos dist 2 2) " m"))
    )
  )

  (if (or (null layer) (= layer ""))
    (setq layer (getvar "CLAYER"))
  )

  ;; Cree le calque s'il n'existe pas
  (if (not (tblsearch "LAYER" layer))
    (command "_.-LAYER" "_M" layer "")
  )

  ;; Decalage de la cote
  (setq decalage 2.0)

  ;; Position de la ligne de cote
  (cond
    ;; Cote horizontale : on decale en Y
    ((= sens "H")
      (setq pos
        (list
          (/ (+ (car p1) (car p2)) 2.0)
          (+ (max (cadr p1) (cadr p2)) decalage)
          0.0
        )
      )
    )

    ;; Cote verticale : on decale en X
    ((= sens "V")
      (setq pos
        (list
          (+ (max (car p1) (car p2)) decalage)
          (/ (+ (cadr p1) (cadr p2)) 2.0)
          0.0
        )
      )
    )
  )

  ;; Sauvegarde des variables
  (setq oldos (getvar "OSMODE"))
  (setq oldlay (getvar "CLAYER"))

  ;; Active le calque voulu
  (setvar "CLAYER" layer)

  ;; Desactive les accrochages
  (setvar "OSMODE" 0)

  ;; Cote lineaire horizontale ou verticale
  (command
    "_.DIMLINEAR"
    "_non" p1
    "_non" p2
    (if (= sens "H") "_H" "_V")
    "_T" texte
    "_non" pos
  )

  ;; Remet les variables comme avant
  (setvar "OSMODE" oldos)
  (setvar "CLAYER" oldlay)

  (princ)
)

(defun draw-cotlin-perso-taille (p1 p2 texte layer taille_txt / pos decalage oldos oldlay olddimtxt dx dy sens dist)
  ;; p1 = premier point mesure
  ;; p2 = deuxieme point mesure
  ;; texte = texte affiche dans la cotation
  ;; layer = calque de la cotation
  ;; taille_txt = taille du texte de cotation
  ;; sens = "H" ou "V" determine automatiquement

  (setq p1 (pt-2d p1))
  (setq p2 (pt-2d p2))

  ;; Ecart horizontal / vertical
  (setq dx (abs (- (car p2) (car p1))))
  (setq dy (abs (- (cadr p2) (cadr p1))))

  ;; Choix automatique du sens
  (setq sens
    (if (>= dx dy)
      "H"
      "V"
    )
  )

  ;; Texte automatique selon le sens de cote
  (if (or (null texte) (= texte ""))
    (progn
      (setq dist
        (if (= sens "H")
          dx
          dy
        )
      )
      (setq texte (strcat (rtos dist 2 2) " m"))
    )
  )

  ;; Calque par defaut
  (if (or (null layer) (= layer ""))
    (setq layer (getvar "CLAYER"))
  )

  ;; Taille texte par defaut ou choix utilisateur
  (if (or (null taille_txt) (<= taille_txt 0))
    (progn
      (setq taille_txt (getreal "\nTaille du texte de cotation <2.5> : "))
      (if (null taille_txt)
        (setq taille_txt 2.5)
      )
    )
  )

  ;; Cree le calque s'il n'existe pas
  (if (not (tblsearch "LAYER" layer))
    (command "_.-LAYER" "_M" layer "")
  )

  ;; Decalage de la cote
  (setq decalage 2.0)

  ;; Position de la ligne de cote
  (cond
    ;; Cote horizontale : on decale en Y
    ((= sens "H")
      (setq pos
        (list
          (/ (+ (car p1) (car p2)) 2.0)
          (+ (max (cadr p1) (cadr p2)) decalage)
          0.0
        )
      )
    )

    ;; Cote verticale : on decale en X
    ((= sens "V")
      (setq pos
        (list
          (+ (max (car p1) (car p2)) decalage)
          (/ (+ (cadr p1) (cadr p2)) 2.0)
          0.0
        )
      )
    )
  )

  ;; Sauvegarde des variables
  (setq oldos (getvar "OSMODE"))
  (setq oldlay (getvar "CLAYER"))
  (setq olddimtxt (getvar "DIMTXT"))

  ;; Active le calque voulu
  (setvar "CLAYER" layer)

  ;; Taille du texte de cotation
  (setvar "DIMTXT" taille_txt)

  ;; Desactive les accrochages
  (setvar "OSMODE" 0)

  ;; Cote lineaire horizontale ou verticale
  (command
    "_.DIMLINEAR"
    "_non" p1
    "_non" p2
    (if (= sens "H") "_H" "_V")
    "_T" texte
    "_non" pos
  )

  ;; Remet les variables comme avant
  (setvar "OSMODE" oldos)
  (setvar "CLAYER" oldlay)
  (setvar "DIMTXT" olddimtxt)

  (princ)
)

(defun draw-circle (pt rayon layer /)
  ;; pt    = coordonnee du centre, exemple : (list 10 20 0)
  ;; rayon = rayon du cercle
  ;; layer = calque du cercle

  ;; Creation du calque si inexistant
  (if (not (tblsearch "LAYER" layer))
    (entmake
      (list
        '(0 . "LAYER")
        '(100 . "AcDbSymbolTableRecord")
        '(100 . "AcDbLayerTableRecord")
        (cons 2 layer)
        '(70 . 0)
        '(62 . 7)
        '(6 . "Continuous")
      )
    )
  )

  ;; Creation du cercle
  (entmake
    (list
      '(0 . "CIRCLE")
      '(100 . "AcDbEntity")
      (cons 8 layer)
      '(100 . "AcDbCircle")
      (cons 10 pt)
      (cons 40 rayon)
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ O_MATHS ------------------------------------------------------------------------------------

(defun deg (rad)
  (* 180.0 (/ rad pi))
)

(defun tanv (a)
  (/ (sin a) (cos a))
)

(defun pt2d (p)
  (list (car p) (cadr p) 0.0)
)

;; ------------------------------------------------------------------------------------ C_O_CENTRE_ELMS ------------------------------------------------------------------------------------

(defun get-ss-bbox-center (ss / i ent obj minpt maxpt pmin pmax xmin ymin xmax ymax)
  (vl-load-com)

  (setq i 0)
  (setq xmin nil ymin nil xmax nil ymax nil)

  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (setq obj (vlax-ename->vla-object ent))

    (if (not (vl-catch-all-error-p
               (vl-catch-all-apply
                 '(lambda ()
                    (vla-getboundingbox obj 'minpt 'maxpt)
                  )
               )
             )
        )
      (progn
        (setq pmin (vlax-safearray->list minpt))
        (setq pmax (vlax-safearray->list maxpt))

        (if (null xmin)
          (progn
            (setq xmin (car pmin))
            (setq ymin (cadr pmin))
            (setq xmax (car pmax))
            (setq ymax (cadr pmax))
          )
          (progn
            (setq xmin (min xmin (car pmin)))
            (setq ymin (min ymin (cadr pmin)))
            (setq xmax (max xmax (car pmax)))
            (setq ymax (max ymax (cadr pmax)))
          )
        )
      )
    )

    (setq i (1+ i))
  )

  (if xmin
    (list
      (/ (+ xmin xmax) 2.0)
      (/ (+ ymin ymax) 2.0)
      0.0
    )
    nil
  )
)

(defun move-selection-by-vector (ss vec / i ent obj)
  (vl-load-com)

  (setq i 0)

  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (setq obj (vlax-ename->vla-object ent))

    (vla-move
      obj
      (vlax-3d-point '(0 0 0))
      (vlax-3d-point vec)
    )

    (setq i (1+ i))
  )
)

(defun c:O_CENTRE_ELMS (/ ss choix p1 p2 p3 p4 centreSel centreDest vec)
  (vl-load-com)

  (princ "\nSelectionner les elements a centrer : ")
  (setq ss (ssget))

  (if ss
    (progn
      (initget "2 4")
      (setq choix (getkword "\nCentrer entre combien de points ? [2/4] <2> : "))

      (if (null choix)
        (setq choix "2")
      )

      (cond
        ;; Centre entre 2 points
        ((= choix "2")
          (setq p1 (getpoint "\nPremier point : "))
          (setq p2 (getpoint "\nDeuxieme point : "))

          (setq centreDest
            (list
              (/ (+ (car p1) (car p2)) 2.0)
              (/ (+ (cadr p1) (cadr p2)) 2.0)
              0.0
            )
          )
        )

        ;; Centre entre 4 points
        ((= choix "4")
          (setq p1 (getpoint "\nPoint 1 : "))
          (setq p2 (getpoint "\nPoint 2 : "))
          (setq p3 (getpoint "\nPoint 3 : "))
          (setq p4 (getpoint "\nPoint 4 : "))

          (setq centreDest
            (list
              (/ (+ (car p1) (car p2) (car p3) (car p4)) 4.0)
              (/ (+ (cadr p1) (cadr p2) (cadr p3) (cadr p4)) 4.0)
              0.0
            )
          )
        )
      )

      ;; Centre actuel de la selection
      (setq centreSel (get-ss-bbox-center ss))

      (if centreSel
        (progn
          ;; Vecteur de déplacement
          (setq vec
            (list
              (- (car centreDest) (car centreSel))
              (- (cadr centreDest) (cadr centreSel))
              0.0
            )
          )

          ;; Déplacement de tous les éléments
          (move-selection-by-vector ss vec)

          (princ "\nSelection centree avec succes.")
        )
        (princ "\nErreur : impossible de calculer le centre de la selection.")
      )
    )
    (princ "\nAucun element selectionne.")
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ C_O_CENTRE_TXT ------------------------------------------------------------------------------------

(defun c:O_CENTRE_TXT (/ mode p1 p2 p3 p4 pts txt mid ang haut choix layer)

  (setq layer "0")

  ;; Choix du mode
  (initget "2 4")
  (setq mode (getkword "\nCentrer le texte avec combien de points ? [2/4] <2> : "))

  (if (null mode)
    (setq mode "2")
  )

  ;; Sélection des points
  (cond
    ((= mode "2")
      (setq p1 (getpoint "\nPremier point : "))
      (setq p2 (getpoint "\nDeuxieme point : "))
    )

    ((= mode "4")
      (setq p1 (getpoint "\nPoint 1 : "))
      (setq p2 (getpoint "\nPoint 2 : "))
      (setq p3 (getpoint "\nPoint 3 : "))
      (setq p4 (getpoint "\nPoint 4 : "))
    )
  )

  ;; Choix TEXT / MTEXT
  (initget "T M")
  (setq choix (getkword "\nType de texte ? [Text/Mtext] <M> : "))

  (if (null choix)
    (setq choix "M")
  )

  ;; Texte
  (setq txt (getstring T "\nTexte a placer : "))

  ;; Hauteur
  (setq haut (getreal "\nHauteur du texte <2.5> : "))

  (if (null haut)
    (setq haut 2.5)
  )

  ;; Calcul du centre
  (cond
    ((= mode "2")
      (setq mid
        (list
          (/ (+ (car p1) (car p2)) 2.0)
          (/ (+ (cadr p1) (cadr p2)) 2.0)
          0.0
        )
      )
    )

    ((= mode "4")
      (setq mid
        (list
          (/ (+ (car p1) (car p2) (car p3) (car p4)) 4.0)
          (/ (+ (cadr p1) (cadr p2) (cadr p3) (cadr p4)) 4.0)
          0.0
        )
      )
    )
  )

  ;; Angle du texte selon l'axe point 1 -> point 2
  (setq ang (angle p1 p2))

  ;; Création du texte
  (cond

    ;; TEXT simple
    ((= choix "T")
      (entmakex
        (list
          '(0 . "TEXT")
          (cons 8 layer)
          (cons 10 mid)
          (cons 11 mid)
          (cons 40 haut)
          (cons 1 txt)
          (cons 50 ang)
          (cons 7 (getvar "TEXTSTYLE"))
          (cons 72 1) ;; centre horizontal
          (cons 73 2) ;; milieu vertical
        )
      )
    )

    ;; MTEXT
    ((= choix "M")
      (entmakex
        (list
          '(0 . "MTEXT")
          (cons 8 layer)
          (cons 10 mid)
          (cons 40 haut)
          (cons 1 txt)
          (cons 50 ang)
          (cons 7 (getvar "TEXTSTYLE"))
          (cons 71 5) ;; attachement milieu centre
          (cons 72 5)
        )
      )
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ C_O_ECHELLE_DISTANCE ------------------------------------------------------------------------------------

(defun c:O_ECHELLE_DISTANCE (/ ss p1 p2 distActuelle distVoulu facteur basePt)
  (princ "\nSelectionner les elements a mettre a l'echelle : ")
  (setq ss (ssget))

  (if ss
    (progn
      ;; Points de reference
      (setq p1 (getpoint "\nPremier point de reference : "))
      (setq p2 (getpoint p1 "\nDeuxieme point de reference : "))

      (if (and p1 p2)
        (progn
          ;; Distance actuelle
          (setq distActuelle (distance p1 p2))

          (if (> distActuelle 0.0)
            (progn
              (princ
                (strcat
                  "\nDistance actuelle : "
                  (rtos distActuelle 2 3)
                )
              )

              ;; Distance voulue
              (setq distVoulu
                (getreal "\nEntrer la distance voulue : ")
              )

              (if (and distVoulu (> distVoulu 0.0))
                (progn
                  ;; Calcul du facteur
                  (setq facteur (/ distVoulu distActuelle))

                  ;; Point de base = premier point clique
                  (setq basePt p1)

                  ;; Mise a l'echelle
                  (command "_.SCALE" ss "" basePt facteur)

                  (princ
                    (strcat
                      "\nMise a l'echelle terminee."
                      "\nFacteur applique : "
                      (rtos facteur 2 6)
                    )
                  )
                )
                (princ "\nErreur : distance voulue invalide.")
              )
            )
            (princ "\nErreur : les deux points sont identiques.")
          )
        )
        (princ "\nErreur : points invalides.")
      )
    )
    (princ "\nAucun element selectionne.")
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ C_O_TXT ------------------------------------------------------------------------------------

(defun upper-fr (c)
  (cond
    ((= c "à") "À")
    ((= c "â") "Â")
    ((= c "ä") "Ä")
    ((= c "é") "É")
    ((= c "è") "È")
    ((= c "ê") "Ê")
    ((= c "ë") "Ë")
    ((= c "î") "Î")
    ((= c "ï") "Ï")
    ((= c "ô") "Ô")
    ((= c "ö") "Ö")
    ((= c "ù") "Ù")
    ((= c "û") "Û")
    ((= c "ü") "Ü")
    ((= c "ç") "Ç")
    (T (strcase c))
  )
)

(defun lower-fr (c)
  (cond
    ((= c "À") "à")
    ((= c "Â") "â")
    ((= c "Ä") "ä")
    ((= c "É") "é")
    ((= c "È") "è")
    ((= c "Ê") "ê")
    ((= c "Ë") "ë")
    ((= c "Î") "î")
    ((= c "Ï") "ï")
    ((= c "Ô") "ô")
    ((= c "Ö") "ö")
    ((= c "Ù") "ù")
    ((= c "Û") "û")
    ((= c "Ü") "ü")
    ((= c "Ç") "ç")
    (T (strcase c T))
  )
)

(defun space-char-p (c)
  (or
    (= c " ")
    (= c "\t")
    (= c "\n")
    (= c "\r")
  )
)

(defun separator-char-p (c)
  (or
    (= c " ")
    (= c "\t")
    (= c "\n")
    (= c "\r")
    (= c "-")
    (= c "_")
    (= c "/")
    (= c ".")
    (= c ",")
    (= c ";")
    (= c ":")
    (= c "(")
    (= c ")")
    (= c "[")
    (= c "]")
    (= c "{")
    (= c "}")
    (= c "|")
  )
)

(defun trim-spaces (s / start end)
  (setq start 1)
  (setq end (strlen s))

  (while
    (and
      (<= start end)
      (space-char-p (substr s start 1))
    )
    (setq start (1+ start))
  )

  (while
    (and
      (>= end start)
      (space-char-p (substr s end 1))
    )
    (setq end (1- end))
  )

  (if (> start end)
    ""
    (substr s start (- end start -1))
  )
)

(defun collapse-spaces (s / i c result lastSpace)
  (setq i 1)
  (setq result "")
  (setq lastSpace nil)

  (while (<= i (strlen s))
    (setq c (substr s i 1))

    (if (space-char-p c)
      (progn
        (if (not lastSpace)
          (progn
            (setq result (strcat result " "))
            (setq lastSpace T)
          )
        )
      )
      (progn
        (setq result (strcat result c))
        (setq lastSpace nil)
      )
    )

    (setq i (1+ i))
  )

  (trim-spaces result)
)

(defun remove-all-spaces (s / i c result)
  (setq i 1)
  (setq result "")

  (while (<= i (strlen s))
    (setq c (substr s i 1))

    (if (not (space-char-p c))
      (setq result (strcat result c))
    )

    (setq i (1+ i))
  )

  result
)

(defun str-upper-fr (s / i c r)
  (setq i 1)
  (setq r "")

  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (setq r (strcat r (upper-fr c)))
    (setq i (1+ i))
  )

  r
)

(defun str-lower-fr (s / i c r)
  (setq i 1)
  (setq r "")

  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (setq r (strcat r (lower-fr c)))
    (setq i (1+ i))
  )

  r
)

(defun capitalize-text-safe (s / i n c c2 result nextCap code)
  (setq s (collapse-spaces s))
  (setq i 1)
  (setq n (strlen s))
  (setq result "")
  (setq nextCap T)

  (while (<= i n)
    (setq c (substr s i 1))

    (cond

      ((= c "\\")
        (setq code "\\")
        (setq i (1+ i))

        (if (<= i n)
          (progn
            (setq c2 (substr s i 1))
            (setq code (strcat code c2))
            (setq i (1+ i))

            (cond
              ((or (= c2 "P") (= c2 "p"))
                (setq result (strcat result code))
                (setq nextCap T)
              )

              ((or
                 (= c2 "L") (= c2 "l")
                 (= c2 "O") (= c2 "o")
                 (= c2 "K") (= c2 "k")
               )
                (setq result (strcat result code))
              )

              (T
                (while
                  (and
                    (<= i n)
                    (/= (substr s i 1) ";")
                  )
                  (setq code (strcat code (substr s i 1)))
                  (setq i (1+ i))
                )

                (if
                  (and
                    (<= i n)
                    (= (substr s i 1) ";")
                  )
                  (progn
                    (setq code (strcat code ";"))
                    (setq i (1+ i))
                  )
                )

                (setq result (strcat result code))
              )
            )
          )
          (setq result (strcat result code))
        )
      )

      ((or (= c "{") (= c "}"))
        (setq result (strcat result c))
        (setq i (1+ i))
      )

      ((separator-char-p c)
        (setq result (strcat result c))
        (setq nextCap T)
        (setq i (1+ i))
      )

      (nextCap
        (setq result (strcat result (upper-fr c)))
        (setq nextCap nil)
        (setq i (1+ i))
      )

      (T
        (setq result (strcat result (lower-fr c)))
        (setq i (1+ i))
      )
    )
  )

  result
)

(defun replace-string (old new str / pos lenold result)
  (setq lenold (strlen old))
  (setq result "")

  (while (setq pos (vl-string-search old str))
    (setq result (strcat result (substr str 1 pos) new))
    (setq str (substr str (+ pos lenold 1)))
  )

  (strcat result str)
)

(defun get-text-value (ent / obj)
  (setq obj (vlax-ename->vla-object ent))
  (vla-get-TextString obj)
)

(defun set-text-value (ent newtxt / obj)
  (setq obj (vlax-ename->vla-object ent))
  (vla-put-TextString obj newtxt)
)

(defun apply-to-text-selection (mode / ss i ent oldtxt newtxt count)
  (princ "\nSelectionner les TEXT / MTEXT : ")
  (setq ss (ssget '((0 . "TEXT,MTEXT"))))
  (setq count 0)

  (if ss
    (progn
      (setq i 0)

      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq oldtxt (get-text-value ent))

        (if oldtxt
          (progn
            (cond
              ((= mode "MAJ")
                (setq newtxt (str-upper-fr oldtxt))
              )

              ((= mode "MIN")
                (setq newtxt (str-lower-fr oldtxt))
              )

              ((= mode "CAP")
                (setq newtxt (capitalize-text-safe oldtxt))
              )

              ((= mode "ESP_TROP")
                (setq newtxt (collapse-spaces oldtxt))
              )

              ((= mode "ESP_TOUT")
                (setq newtxt (remove-all-spaces oldtxt))
              )
            )

            (if (/= oldtxt newtxt)
              (progn
                (set-text-value ent newtxt)
                (setq count (1+ count))
              )
            )
          )
        )

        (setq i (1+ i))
      )

      (princ
        (strcat
          "\n"
          (itoa count)
          " texte(s) modifie(s)."
        )
      )
    )
    (princ "\nAucun TEXT ou MTEXT selectionne.")
  )

  (princ)
)

(defun apply-spaces-to-text-selection (/ choix mode)
  (initget "TO TR")
  (setq choix
    (getkword
      "\nType de suppression des espaces [TOut/TRop] <TR> : "
    )
  )

  (if (null choix)
    (setq choix "TR")
  )

  (cond
    ((= choix "TO")
      (setq mode "ESP_TOUT")
    )

    ((= choix "TR")
      (setq mode "ESP_TROP")
    )
  )

  (apply-to-text-selection mode)
)

(defun apply-replace-to-text-selection (/ ss old new i ent oldtxt newtxt count)
  (vl-load-com)

  (setq old (getstring T "\nTexte a remplacer : "))

  (if (= old "")
    (progn
      (princ "\nErreur : le texte a remplacer ne peut pas etre vide.")
      (exit)
    )
  )

  (setq new (getstring T "\nNouveau texte : "))

  (princ "\nSelectionner les TEXT / MTEXT a modifier : ")
  (setq ss (ssget '((0 . "TEXT,MTEXT"))))
  (setq count 0)

  (if ss
    (progn
      (setq i 0)

      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq oldtxt (get-text-value ent))

        (if oldtxt
          (progn
            (setq newtxt (replace-string old new oldtxt))

            (if (/= oldtxt newtxt)
              (progn
                (set-text-value ent newtxt)
                (setq count (1+ count))
              )
            )
          )
        )

        (setq i (1+ i))
      )

      (princ
        (strcat
          "\nRemplacement termine. "
          (itoa count)
          " texte(s) modifie(s)."
        )
      )
    )
    (princ "\nAucun TEXT ou MTEXT selectionne.")
  )

  (princ)
)


(defun c:O_TXT (/ choix)
  (vl-load-com)

  (initget "MA MI C E R")
  (setq choix
    (getkword
      "\nAction sur le texte [MAjuscule/MInuscule/Capitaliser/Espaces/Remplacer] <C> : "
    )
  )

  (if (null choix)
    (setq choix "C")
  )

  (cond
    ((= choix "MA")
      (apply-to-text-selection "MAJ")
    )

    ((= choix "MI")
      (apply-to-text-selection "MIN")
    )

    ((= choix "C")
      (apply-to-text-selection "CAP")
    )

    ((= choix "E")
      (apply-spaces-to-text-selection)
    )

    ((= choix "R")
      (apply-replace-to-text-selection)
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ C_S_CAMERA ------------------------------------------------------------------------------------

(vl-load-com)

(setq *SC3D_PI* 3.141592653589793)
(setq *SC3D_PPM_SOLID_Z* -0.050)
(setq *SC3D_PPM_EDGE_Z* -0.045)
(setq *SC3D_APP* "SC3D_CAMERA")
(setq *SC3D_CFG_FOLDER* "BricsCAD")
(setq *SC3D_CFG_FILE* "camera.config")

(setq *SC3D_SENSOR_LIST*
  '(
    "1/6"
    "1/4"
    "1/3.6"
    "1/3"
    "1/2.8"
    "1/2.7"
    "1/2.5"
    "1/2"
    "1/1.8"
    "2/3"
    "1"
    "1.25"
  )
)

(setq *SC3D_RES_LIST*
  '(
    "320x240 (4:3)"
    "384x288 (4:3)"
    "480x360 (4:3)"
    "640x480 (4:3)"
    "640x512 (0.3MP 5:4)"
    "768x494 (0.4MP 4:3)"
    "752x582 (0.4MP 4:3)"
    "800x600 (0.5MP 4:3)"
    "1020x596 (0.6MP 16:9)"
    "1280x720 (1MP 16:9)"
    "1280x960 (1.2MP 4:3)"
    "1280x1024 (1.3MP 5:4)"
    "1600x1200 (2MP 4:3)"
    "1920x1080 (2MP 16:9)"
    "2288x1288 (3MP 16:9)"
    "2048x1536 (3MP 4:3)"
    "2288x1712 (4MP 4:3)"
    "2560x1440 (4MP 16:9)"
    "2560x1920 (5MP 4:3)"
    "2592x1520 (4MP 17:10)"
    "2592x1944 (5MP 4:3)"
    "2600x1950 (5MP 4:3)"
    "2688x1520 (4MP 16:9)"
    "3072x1728 (5MP 16:9)"
    "3072x2048 (6MP 3:2)"
    "3296x2472 (8MP 4:3)"
    "3840x2160 (8MP 16:9)"
    "3648x2752 (10MP 4:3)"
    "4000x2672 (11MP 3:2)"
    "4000x3000 (12MP 4:3)"
    "4864x3248 (16MP 3:2)"
    "5120x3840 (19MP 4:3)"
    "6576x4384 (29MP 3:2)"
  )
)

(setq *SC3D_STD_LIST* '("2014" "2025"))
(setq *SC3D_VIEW_LIST* '("Vue du dessus" "Vue de cote"))
(setq *SC3D_SIT_LIST* '("Aucune" "Existante" "Projetee"))
(setq *SC3D_HACHURE_PATTERNS* '("ANSI31" "ANSI32" "ANSI33" "ANSI34" "ANSI35" "ANSI36" "ANSI37" "ANSI38" "ANGLE"))
(setq *SC3D_RAND_SEED* nil)

;; Polygone d'ajustement courant (liste de points 2D en coordonnees locales du bloc)
;; et sa triangulation, utilises par les primitives de dessin pour decouper la
;; geometrie elles-memes (voir section CLIPPING). nil = pas d'ajustement actif.
(setq *SC3D_CLIP_POLY* nil)
(setq *SC3D_CLIP_TRIS* nil)

(defun SC3D:VIEW-LABEL->CODE (v)
  (if (= v "Vue de cote") "SIDE" "TOP")
)

(defun SC3D:VIEW-CODE->LABEL (v)
  (if (= v "SIDE") "Vue de cote" "Vue du dessus")
)

;; ------------------------------------------------------------------------------------
;; NOM DU CHAMP DE VISION / SITUATION (Existante ou Projetee)
;; Les deux sont optionnels. La situation ne peut valoir qu'une seule des deux valeurs.
;; ------------------------------------------------------------------------------------

(defun SC3D:SIT-LABEL->CODE (s)
  (cond
    ((= s "Existante") "EXIST")
    ((= s "Projetee") "PROJ")
    (T "")
  )
)

(defun SC3D:SIT-CODE->LABEL (s)
  (cond
    ((= s "EXIST") "Existante")
    ((= s "PROJ") "Projetee")
    (T "Aucune")
  )
)

(defun SC3D:CLEAN-NAME (s)
  ;; Le nom est stocke dans la chaine de configuration separee par "|" :
  ;; on interdit donc ce caractere dans le nom.
  (if (null s) (setq s ""))
  (SC3D:REPL s "|" "/")
)

(defun SC3D:INIT-RAND ()
  (setq *SC3D_RAND_SEED* (abs (fix (* (getvar "CDATE") 100000000))))
)

(defun SC3D:RAND ()
  (if (null *SC3D_RAND_SEED*) (SC3D:INIT-RAND))
  (setq *SC3D_RAND_SEED*
    (fix (abs (rem (+ (* (float *SC3D_RAND_SEED*) 1103515245.0) 12345.0) 2147483647.0)))
  )
  *SC3D_RAND_SEED*
)

(defun SC3D:RAND-ITEM (lst)
  (nth (fix (rem (SC3D:RAND) (length lst))) lst)
)

(defun SC3D:RAND-HATCH ()
  (setq *SC3D_CUR_HATCH_PAT* (SC3D:RAND-ITEM *SC3D_HACHURE_PATTERNS*))
  (setq *SC3D_CUR_HATCH_COL* (fix (+ 1 (rem (SC3D:RAND) 254))))
  (while (or (= *SC3D_CUR_HATCH_COL* 7) (= *SC3D_CUR_HATCH_COL* 0))
    (setq *SC3D_CUR_HATCH_COL* (fix (+ 1 (rem (SC3D:RAND) 254))))
  )
)

(defun SC3D:DTR (a) (* *SC3D_PI* (/ a 180.0)))
(defun SC3D:RTD (a) (* 180.0 (/ a *SC3D_PI*)))
(defun SC3D:TAN (a) (/ (sin a) (cos a)))
(defun SC3D:MAX (a b) (if (> a b) a b))
(defun SC3D:MIN (a b) (if (< a b) a b))
(defun SC3D:RGB (r g b) (+ (* r 65536) (* g 256) b))

;; Toute la geometrie (bloc, INSERT, xdata de decoupe) est stockee en WCS/OCS
;; brut via entmake. Les points et angles saisis interactivement (getpoint,
;; getcorner, getangle) sont eux exprimes dans l'UCS courant : si l'UCS n'est
;; pas le WCS (UCS "General"), il faut donc toujours les convertir avant de
;; les combiner avec des donnees d'entite. cf. SC3D:UCS-PT->WCS / SC3D:UCS-ANG->WCS.
(defun SC3D:UCS-PT->WCS (pt) (trans pt 1 0))

(defun SC3D:UCS-ANG->WCS (a / p0 p1)
  (setq p0 (trans '(0.0 0.0 0.0) 1 0))
  (setq p1 (trans (list (cos a) (sin a) 0.0) 1 0))
  (angle p0 p1)
)

(defun SC3D:TRANS-DXF (tr / opacity)
  (if (< tr 0.0) (setq tr 0.0))
  (if (> tr 90.0) (setq tr 90.0))
  (setq opacity (fix (* 255.0 (/ (- 100.0 tr) 100.0))))
  (+ 33554432 opacity)
)

(defun SC3D:SETVAL (lst key val / out found)
  (setq out '())
  (setq found nil)
  (foreach x lst
    (if (= (car x) key)
      (progn
        (setq out (append out (list (cons key val))))
        (setq found T)
      )
      (setq out (append out (list x)))
    )
  )
  (if found out (append out (list (cons key val))))
)

(defun SC3D:REPL (s old new / p)
  (while (setq p (vl-string-search old s))
    (setq s (strcat (substr s 1 p) new (substr s (+ p 1 (strlen old)))))
  )
  s
)

(defun SC3D:ATOF (s def)
  (if (or (null s) (= s ""))
    def
    (atof (SC3D:REPL s "," "."))
  )
)

(defun SC3D:CLEAN (s)
  (strcase
    (SC3D:REPL
      (SC3D:REPL
        (SC3D:REPL
          (SC3D:REPL s "\"" "")
          " " ""
        )
        "," "."
      )
      "'" ""
    )
  )
)

(defun SC3D:INDEXOF (item lst / i r)
  (setq i 0)
  (setq r nil)
  (foreach x lst
    (if (= x item) (setq r i))
    (setq i (+ i 1))
  )
  (if r r 0)
)

(defun SC3D:UNIQUE (lst / out)
  (setq out '())
  (foreach x lst
    (if (not (member x out))
      (setq out (append out (list x)))
    )
  )
  out
)

(defun SC3D:SPLIT (s sep / p out)
  (setq out '())
  (while (setq p (vl-string-search sep s))
    (setq out (append out (list (substr s 1 p))))
    (setq s (substr s (+ p 1 (strlen sep))))
  )
  (append out (list s))
)

(defun SC3D:JOIN (lst sep / out first x)
  (setq out "")
  (setq first T)
  (foreach x lst
    (setq out (if first x (strcat out sep x)))
    (setq first nil)
  )
  out
)

(defun SC3D:RES-BASIC (s / p)
  (setq p (vl-string-search " " s))
  (if p
    (substr s 1 p)
    s
  )
)

(defun SC3D:PARSE-RES (s / p w h)
  (setq s (SC3D:REPL (strcase s) " " ""))
  (setq p (vl-string-search "X" s))
  (if p
    (progn
      (setq w (atoi (substr s 1 p)))
      (setq h (atoi (substr s (+ p 2))))
      (if (or (= w 0) (= h 0))
        (list 1920 1080)
        (list w h)
      )
    )
    (list 1920 1080)
  )
)

(defun SC3D:SENSOR-WIDTH (fmt / f tab v)
  (setq f (SC3D:CLEAN fmt))
  (setq tab
    '(
      ("1/6" . 2.40)
      ("1/4" . 3.60)
      ("1/3.6" . 4.00)
      ("1/3" . 4.80)
      ("1/2.8" . 5.27)
      ("1/2.7" . 5.37)
      ("1/2.5" . 5.76)
      ("1/2" . 6.40)
      ("1/1.8" . 7.18)
      ("2/3" . 8.80)
      ("1" . 12.80)
      ("1.25" . 16.22)
    )
  )
  (setq v (cdr (assoc f tab)))
  (if v v 5.27)
)

(defun SC3D:DOCS-PATH (/ p)
  (setq p (getenv "USERPROFILE"))
  (if p
    (strcat p "\\Documents")
    (getvar "DWGPREFIX")
  )
)

(defun SC3D:CFG-DIR (/ dir)
  (setq dir (strcat (SC3D:DOCS-PATH) "\\" *SC3D_CFG_FOLDER*))
  (if (not (vl-file-directory-p dir))
    (vl-mkdir dir)
  )
  dir
)

(defun SC3D:CFG-PATH ()
  (strcat (SC3D:CFG-DIR) "\\" *SC3D_CFG_FILE*)
)

(defun SC3D:READ-LINES (path / f line out)
  (setq out '())
  (if (findfile path)
    (progn
      (setq f (open path "r"))
      (while (setq line (read-line f))
        (if (/= line "")
          (setq out (append out (list line)))
        )
      )
      (close f)
    )
  )
  out
)

(defun SC3D:WRITE-LINES (path lines / f)
  (setq f (open path "w"))
  (foreach l lines
    (write-line l f)
  )
  (close f)
)

(defun SC3D:CAM-LINE->ALIST (line / p)
  ;; Format camera.config :
  ;; fabricant|modele|capteur|resolution|focaleMin|focaleMax|angleHMinFocale|angleHMaxFocale|angleVMinFocale|angleVMaxFocale
  ;; Exemple JVSG Hanwha : Hanwha Vision|XNO-6083R|1/2.8|1920x1080 (2MP 16:9)|2.8|12|120|27|63|15.4
  (setq p (SC3D:SPLIT line "|"))
  (if (>= (length p) 6)
    (list
      (cons 'manu  (nth 0 p))
      (cons 'model (nth 1 p))
      (cons 'fmt   (nth 2 p))
      (cons 'res   (nth 3 p))
      (cons 'fmin  (SC3D:ATOF (nth 4 p) 0.0))
      (cons 'fmax  (SC3D:ATOF (nth 5 p) 999.0))
      (cons 'hmax  (if (>= (length p) 7)  (SC3D:ATOF (nth 6 p) 0.0) 0.0))
      (cons 'hmin  (if (>= (length p) 8)  (SC3D:ATOF (nth 7 p) 0.0) 0.0))
      (cons 'vmax  (if (>= (length p) 9)  (SC3D:ATOF (nth 8 p) 0.0) 0.0))
      (cons 'vmin  (if (>= (length p) 10) (SC3D:ATOF (nth 9 p) 0.0) 0.0))
    )
    nil
  )
)

(defun SC3D:CAM-ALIST->LINE (cam / hmax hmin vmax vmin)
  (setq hmax (if (cdr (assoc 'hmax cam)) (cdr (assoc 'hmax cam)) 0.0))
  (setq hmin (if (cdr (assoc 'hmin cam)) (cdr (assoc 'hmin cam)) 0.0))
  (setq vmax (if (cdr (assoc 'vmax cam)) (cdr (assoc 'vmax cam)) 0.0))
  (setq vmin (if (cdr (assoc 'vmin cam)) (cdr (assoc 'vmin cam)) 0.0))
  (strcat
    (cdr (assoc 'manu cam)) "|"
    (cdr (assoc 'model cam)) "|"
    (cdr (assoc 'fmt cam)) "|"
    (cdr (assoc 'res cam)) "|"
    (rtos (cdr (assoc 'fmin cam)) 2 6) "|"
    (rtos (cdr (assoc 'fmax cam)) 2 6) "|"
    (rtos hmax 2 6) "|"
    (rtos hmin 2 6) "|"
    (rtos vmax 2 6) "|"
    (rtos vmin 2 6)
  )
)

(defun SC3D:LOAD-CAMERAS (/ lines out cam)
  (setq out '())
  (foreach l (SC3D:READ-LINES (SC3D:CFG-PATH))
    (setq cam (SC3D:CAM-LINE->ALIST l))
    (if cam
      (setq out (append out (list cam)))
    )
  )
  out
)

(defun SC3D:SAVE-CAMERAS (cams / lines)
  (setq lines '())
  (foreach cam cams
    (setq lines (append lines (list (SC3D:CAM-ALIST->LINE cam))))
  )
  (SC3D:WRITE-LINES (SC3D:CFG-PATH) lines)
)

(defun SC3D:CAM-MFR-LIST (/ cams out)
  (setq cams (SC3D:LOAD-CAMERAS))
  (setq out '("Manuel"))
  (foreach cam cams
    (setq out (append out (list (cdr (assoc 'manu cam)))))
  )
  (SC3D:UNIQUE out)
)

(defun SC3D:CAM-MODEL-LIST (manu / cams out)
  (if (= manu "Manuel")
    '("Manuel")
    (progn
      (setq cams (SC3D:LOAD-CAMERAS))
      (setq out '())
      (foreach cam cams
        (if (= (cdr (assoc 'manu cam)) manu)
          (setq out (append out (list (cdr (assoc 'model cam)))))
        )
      )
      (if out out '("Manuel"))
    )
  )
)

(defun SC3D:FIND-CAMERA (manu model / cams found)
  (setq cams (SC3D:LOAD-CAMERAS))
  (setq found nil)
  (foreach cam cams
    (if (and (= (cdr (assoc 'manu cam)) manu) (= (cdr (assoc 'model cam)) model))
      (setq found cam)
    )
  )
  found
)

(defun SC3D:BOOLSTR (b)
  (if b "1" "0")
)

(defun SC3D:CFG-STR (vals textHandle / manu model fmt focal res dist camh objh rot std grid trans view useHatch hatchPat hatchCol hidden showDist cvname sit)
  (setq manu     (cdr (assoc 'manu vals)))
  (setq model    (cdr (assoc 'model vals)))
  (setq fmt      (cdr (assoc 'fmt vals)))
  (setq focal    (cdr (assoc 'focal vals)))
  (setq res      (cdr (assoc 'res vals)))
  (setq dist     (cdr (assoc 'dist vals)))
  (setq camh     (cdr (assoc 'camh vals)))
  (setq objh     (cdr (assoc 'objh vals)))
  (setq rot      (cdr (assoc 'rot vals)))
  (setq std      (cdr (assoc 'std vals)))
  (setq grid     (cdr (assoc 'grid vals)))
  (setq trans    (cdr (assoc 'trans vals)))
  (setq view     (cdr (assoc 'view vals)))
  (setq useHatch (cdr (assoc 'use_hatch vals)))
  (setq hatchPat (cdr (assoc 'hatch_pattern vals)))
  (setq hatchCol (cdr (assoc 'hatch_color vals)))
  (setq hidden   (cdr (assoc 'hidden vals)))
  ;; Absent (anciennes configs) = affiche par defaut.
  (setq showDist (if (assoc 'show_dist vals) (cdr (assoc 'show_dist vals)) T))
  (setq cvname   (cdr (assoc 'cvname vals)))
  (setq sit      (cdr (assoc 'situation vals)))

  (if (null view)     (setq view "TOP"))
  (if (null hatchPat) (setq hatchPat "ANSI31"))
  (if (null hatchCol) (setq hatchCol 1))
  (if (null cvname)   (setq cvname ""))
  (if (null sit)      (setq sit ""))

  (strcat
    manu "|"
    model "|"
    fmt "|"
    "0.000000|"
    (rtos focal 2 6) "|"
    res "|"
    (rtos dist 2 6) "|"
    (rtos camh 2 6) "|"
    (rtos objh 2 6) "|"
    (rtos rot 2 6) "|"
    std "|"
    (SC3D:BOOLSTR grid) "|"
    (rtos trans 2 6) "|"
    textHandle "|"
    view "|"
    (SC3D:BOOLSTR useHatch) "|"
    hatchPat "|"
    (itoa hatchCol) "|"
    (SC3D:BOOLSTR hidden) "|"
    (SC3D:BOOLSTR showDist) "|"
    (SC3D:CLEAN-NAME cvname) "|"
    sit
  )
)

(defun SC3D:CFG-VALS (cfg / p)
  (setq p (SC3D:SPLIT cfg "|"))
  (if (>= (length p) 13)
    (list
      (cons 'manu (nth 0 p))
      (cons 'model (nth 1 p))
      (cons 'fmt (nth 2 p))
      (cons 'sensorw 0.0)
      (cons 'focal (SC3D:ATOF (nth 4 p) 5.0))
      (cons 'res (nth 5 p))
      (cons 'dist (SC3D:ATOF (nth 6 p) 15.0))
      (cons 'camh (SC3D:ATOF (nth 7 p) 4.0))
      (cons 'objh (SC3D:ATOF (nth 8 p) 2.5))
      (cons 'rot (SC3D:ATOF (nth 9 p) 0.0))
      (cons 'std (nth 10 p))
      (cons 'grid (= (nth 11 p) "1"))
      (cons 'trans (SC3D:ATOF (nth 12 p) 60.0))
      (cons 'texth (if (> (length p) 13) (nth 13 p) ""))
      (cons 'view (if (> (length p) 14) (nth 14 p) "TOP"))
      (cons 'use_hatch (if (> (length p) 15) (= (nth 15 p) "1") nil))
      (cons 'hatch_pattern (if (> (length p) 16) (nth 16 p) "ANSI31"))
      (cons 'hatch_color (if (> (length p) 17) (atoi (nth 17 p)) 1))
      (cons 'hidden (if (> (length p) 18) (= (nth 18 p) "1") nil))
      ;; Absent (anciennes configs generees avant cette option) = affiche par defaut.
      (cons 'show_dist (if (> (length p) 19) (= (nth 19 p) "1") T))
      ;; Nom du champ de vision et situation (anciennes configs = vide).
      (cons 'cvname (if (> (length p) 20) (nth 20 p) ""))
      (cons 'situation (if (> (length p) 21) (nth 21 p) ""))
    )
    nil
  )
)

(defun SC3D:REGAPP ()
  (if (not (tblsearch "APPID" *SC3D_APP*))
    (regapp *SC3D_APP*)
  )
)

(defun SC3D:SET-XDATA (e cfg / ed)
  (SC3D:REGAPP)
  (setq ed (entget e))
  (entmod
    (append
      ed
      (list
        (list -3
          (list
            *SC3D_APP*
            (cons 1000 cfg)
          )
        )
      )
    )
  )
  (entupd e)
)

(defun SC3D:GET-XDATA (e / xd app)
  (setq xd (cdr (assoc -3 (entget e (list *SC3D_APP*)))))
  (if xd
    (progn
      (setq app (assoc *SC3D_APP* xd))
      (if app
        (cdr (assoc 1000 (cdr app)))
        nil
      )
    )
    nil
  )
)

(defun SC3D:MAKE-DCL (/ fn f)
  (setq fn (strcat (getvar "TEMPPREFIX") "sc3d_camera_jvsg.dcl"))
  (setq f (open fn "w"))

  (write-line "sc3d_dialog : dialog {" f)
  (write-line "  label = \"SNCF - Champ de vision camera\";" f)
  (write-line "  width = 65;" f)
  (write-line "  : column {" f)

  (write-line "    : boxed_column {" f)
  (write-line "      label = \"1. Camera\";" f)
  (write-line "      : popup_list { key = \"manu\"; label = \"Fabricant\"; width = 38; }" f)
  (write-line "      : popup_list { key = \"model\"; label = \"Modele\"; width = 38; }" f)
  (write-line "      : edit_box { key = \"camname\"; label = \"Nom du champ (optionnel)\"; edit_width = 24; }" f)
  (write-line "      : popup_list { key = \"situation\"; label = \"Situation\"; width = 22; }" f)
  (write-line "    }" f)

  (write-line "    : boxed_column {" f)
  (write-line "      label = \"2. Optique et resolution\";" f)
  (write-line "      : popup_list { key = \"fmt\"; label = \"Capteur\"; width = 38; }" f)
  (write-line "      : popup_list { key = \"res\"; label = \"Resolution\"; width = 38; }" f)
  (write-line "      : edit_box { key = \"focal\"; label = \"Focale mm\"; edit_width = 10; }" f)
  (write-line "      : text { key = \"caminfo\"; label = \"\"; width = 48; }" f)
  (write-line "    }" f)

  (write-line "    : boxed_column {" f)
  (write-line "      label = \"3. Implantation\";" f)
  (write-line "      : edit_box { key = \"dist\"; label = \"Distance max (m)\"; edit_width = 10; }" f)
  (write-line "      : edit_box { key = \"camh\"; label = \"Hauteur camera (m)\"; edit_width = 10; }" f)
  (write-line "      : edit_box { key = \"objh\"; label = \"Hauteur objectif (m)\"; edit_width = 10; }" f)
  (write-line "      : popup_list { key = \"std\"; label = \"DORI\"; width = 12; }" f)
  (write-line "    }" f)

  (write-line "    : boxed_column {" f)
  (write-line "      label = \"4. Affichage\";" f)
  (write-line "      : popup_list { key = \"view\"; label = \"Vue\"; width = 22; }" f)
  (write-line "      : toggle { key = \"grid\"; label = \"Afficher la grille\"; }" f)
  (write-line "      : toggle { key = \"show_dist\"; label = \"Afficher les metres dans l'axe\"; }" f)
  (write-line "      : edit_box { key = \"trans\"; label = \"Transparence (0-90%)\"; edit_width = 10; }" f)
  (write-line "      : toggle { key = \"use_hatch\"; label = \"Hachure unique (vue du dessus, au lieu des zones PPM)\"; }" f)
  (write-line "      : row {" f)
  (write-line "        : text { key = \"hatch_info\"; label = \"Motif : ANSI31  Couleur : 1\"; width = 38; }" f)
  (write-line "        : button { key = \"btn_regen\"; label = \"Generer\"; width = 10; }" f)
  (write-line "      }" f)
  (write-line "    }" f)

  (write-line "    : errtile { key = \"msg\"; }" f)
  (write-line "    ok_cancel;" f)
  (write-line "  }" f)
  (write-line "}" f)

  (close f)
  fn
)

(defun SC3D:DLG-HATCH-UPDATE ()
  (if (= (get_tile "use_hatch") "1")
    (mode_tile "btn_regen" 0)
    (mode_tile "btn_regen" 1)
  )
)

(defun SC3D:DLG-REGEN-HATCH ()
  (SC3D:RAND-HATCH)
  (set_tile "hatch_info"
    (strcat "Motif : " *SC3D_CUR_HATCH_PAT* "  Couleur ACI : " (itoa *SC3D_CUR_HATCH_COL*))
  )
)

(defun SC3D:SET-POPUP-LIST (key lst val)
  (start_list key 3)
  (mapcar 'add_list lst)
  (end_list)
  (set_tile key (itoa (SC3D:INDEXOF val lst)))
)

(defun SC3D:CUR-MANU ()
  (nth (atoi (get_tile "manu")) *SC3D_MFR_LIST*)
)

(defun SC3D:CUR-MODEL ()
  (nth (atoi (get_tile "model")) *SC3D_MODEL_LIST*)
)

(defun SC3D:CAM-DLG-UPDATE-MODELS (/ manu)
  (setq manu (SC3D:CUR-MANU))
  (setq *SC3D_MODEL_LIST* (SC3D:CAM-MODEL-LIST manu))
  (SC3D:SET-POPUP-LIST "model" *SC3D_MODEL_LIST* (car *SC3D_MODEL_LIST*))
  (SC3D:CAM-DLG-APPLY)
)

(defun SC3D:CAM-DLG-APPLY (/ manu model cam fmt res fmin fmax)
  (setq manu (SC3D:CUR-MANU))
  (setq model (SC3D:CUR-MODEL))

  (if (and (/= manu "Manuel") (/= model "Manuel"))
    (progn
      (setq cam (SC3D:FIND-CAMERA manu model))
      (if cam
        (progn
          (setq fmt (cdr (assoc 'fmt cam)))
          (setq res (cdr (assoc 'res cam)))
          (setq fmin (cdr (assoc 'fmin cam)))
          (setq fmax (cdr (assoc 'fmax cam)))

          (set_tile "fmt" (itoa (SC3D:INDEXOF fmt *SC3D_SENSOR_LIST*)))
          (set_tile "res" (itoa (SC3D:INDEXOF res *SC3D_RES_LIST*)))
          (mode_tile "fmt" 1)
          (mode_tile "res" 1)

          (set_tile "caminfo"
            (strcat
              "Focale de "
              (rtos fmin 2 1)
              " a "
              (rtos fmax 2 1)
              " mm / H "
              (rtos (cdr (assoc 'hmax cam)) 2 1)
              " a "
              (rtos (cdr (assoc 'hmin cam)) 2 1)
              " deg / V "
              (rtos (cdr (assoc 'vmax cam)) 2 1)
              " a "
              (rtos (cdr (assoc 'vmin cam)) 2 1)
              " deg"
            )
          )
        )
      )
    )
    (progn
      (mode_tile "fmt" 0)
      (mode_tile "res" 0)
      (set_tile "caminfo" "Mode manuel : capteur, resolution et focale libres.")
    )
  )
)

(defun SC3D:READ-DLG ()
  (list
    (cons 'manu (SC3D:CUR-MANU))
    (cons 'model (SC3D:CUR-MODEL))
    (cons 'fmt (nth (atoi (get_tile "fmt")) *SC3D_SENSOR_LIST*))
    (cons 'sensorw 0.0)
    (cons 'focal (SC3D:ATOF (get_tile "focal") 5.0))
    (cons 'res (nth (atoi (get_tile "res")) *SC3D_RES_LIST*))
    (cons 'dist (SC3D:ATOF (get_tile "dist") 15.0))
    (cons 'camh (SC3D:ATOF (get_tile "camh") 4.0))
    (cons 'objh (SC3D:ATOF (get_tile "objh") 2.5))
    (cons 'std (nth (atoi (get_tile "std")) *SC3D_STD_LIST*))
    (cons 'view (SC3D:VIEW-LABEL->CODE (nth (atoi (get_tile "view")) *SC3D_VIEW_LIST*)))
    (cons 'grid (= (get_tile "grid") "1"))
    (cons 'show_dist (= (get_tile "show_dist") "1"))
    (cons 'trans (SC3D:ATOF (get_tile "trans") 60.0))
    (cons 'use_hatch (= (get_tile "use_hatch") "1"))
    (cons 'hatch_pattern (if *SC3D_CUR_HATCH_PAT* *SC3D_CUR_HATCH_PAT* "ANSI31"))
    (cons 'hatch_color (if *SC3D_CUR_HATCH_COL* *SC3D_CUR_HATCH_COL* 1))
    (cons 'cvname (SC3D:CLEAN-NAME (get_tile "camname")))
    (cons 'situation (SC3D:SIT-LABEL->CODE (nth (atoi (get_tile "situation")) *SC3D_SIT_LIST*)))
  )
)

(defun SC3D:ACCEPT-DLG (/ vals manu model cam f fmin fmax)
  (setq vals (SC3D:READ-DLG))
  (setq manu (cdr (assoc 'manu vals)))
  (setq model (cdr (assoc 'model vals)))
  (setq f (cdr (assoc 'focal vals)))

  (if (and (/= manu "Manuel") (/= model "Manuel"))
    (progn
      (setq cam (SC3D:FIND-CAMERA manu model))
      (if cam
        (progn
          (setq fmin (cdr (assoc 'fmin cam)))
          (setq fmax (cdr (assoc 'fmax cam)))

          (if (or (< f fmin) (> f fmax))
            (set_tile "msg"
              (strcat
                "/!\\ Focale impossible pour ce modele. Valeur autorisee : "
                (rtos fmin 2 1)
                " a "
                (rtos fmax 2 1)
                " mm."
              )
            )
            (progn
              (setq SC3D_DLG_RET vals)
              (done_dialog 1)
            )
          )
        )
      )
    )
    (progn
      (setq SC3D_DLG_RET vals)
      (done_dialog 1)
    )
  )
)

(defun SC3D:DIALOG (def / dcl id result fmt res std manu model)
  (setq dcl (SC3D:MAKE-DCL))
  (setq id (load_dialog dcl))

  (if (not (new_dialog "sc3d_dialog" id))
    nil
    (progn
      (setq *SC3D_MFR_LIST* (SC3D:CAM-MFR-LIST))

      (start_list "manu")
      (mapcar 'add_list *SC3D_MFR_LIST*)
      (end_list)

      (start_list "fmt")
      (mapcar 'add_list *SC3D_SENSOR_LIST*)
      (end_list)

      (start_list "res")
      (mapcar 'add_list *SC3D_RES_LIST*)
      (end_list)

      (start_list "std")
      (mapcar 'add_list *SC3D_STD_LIST*)
      (end_list)

      (start_list "view")
      (mapcar 'add_list *SC3D_VIEW_LIST*)
      (end_list)

      (start_list "situation")
      (mapcar 'add_list *SC3D_SIT_LIST*)
      (end_list)

      (if def
        (progn
          (setq manu (cdr (assoc 'manu def)))
          (setq model (cdr (assoc 'model def)))
          (if (not manu) (setq manu "Manuel"))
          (if (not model) (setq model "Manuel"))

          (set_tile "manu" (itoa (SC3D:INDEXOF manu *SC3D_MFR_LIST*)))
          (setq *SC3D_MODEL_LIST* (SC3D:CAM-MODEL-LIST manu))
          (SC3D:SET-POPUP-LIST "model" *SC3D_MODEL_LIST* model)

          (setq fmt (cdr (assoc 'fmt def)))
          (setq res (cdr (assoc 'res def)))
          (setq std (cdr (assoc 'std def)))

          (set_tile "fmt" (itoa (SC3D:INDEXOF fmt *SC3D_SENSOR_LIST*)))
          (set_tile "res" (itoa (SC3D:INDEXOF res *SC3D_RES_LIST*)))
          (set_tile "std" (itoa (SC3D:INDEXOF std *SC3D_STD_LIST*)))
          (set_tile "view" (itoa (SC3D:INDEXOF (SC3D:VIEW-CODE->LABEL (cdr (assoc 'view def))) *SC3D_VIEW_LIST*)))

          (set_tile "camname" (if (cdr (assoc 'cvname def)) (cdr (assoc 'cvname def)) ""))
          (set_tile "situation"
            (itoa (SC3D:INDEXOF (SC3D:SIT-CODE->LABEL (cdr (assoc 'situation def))) *SC3D_SIT_LIST*))
          )

          (set_tile "focal" (rtos (cdr (assoc 'focal def)) 2 2))
          (set_tile "dist" (rtos (cdr (assoc 'dist def)) 2 2))
          (set_tile "camh" (rtos (cdr (assoc 'camh def)) 2 2))
          (set_tile "objh" (rtos (cdr (assoc 'objh def)) 2 2))
          (set_tile "grid" (if (cdr (assoc 'grid def)) "1" "0"))
          ;; Absent (anciennes configs) = affiche par defaut.
          (set_tile "show_dist" (if (or (not (assoc 'show_dist def)) (cdr (assoc 'show_dist def))) "1" "0"))
          (set_tile "trans" (rtos (cdr (assoc 'trans def)) 2 0))

          (setq *SC3D_CUR_HATCH_PAT* (cdr (assoc 'hatch_pattern def)))
          (setq *SC3D_CUR_HATCH_COL* (cdr (assoc 'hatch_color def)))
          (if (null *SC3D_CUR_HATCH_PAT*) (setq *SC3D_CUR_HATCH_PAT* "ANSI31"))
          (if (null *SC3D_CUR_HATCH_COL*) (setq *SC3D_CUR_HATCH_COL* 1))
          (set_tile "use_hatch" (if (cdr (assoc 'use_hatch def)) "1" "0"))
        )
        (progn
          (set_tile "manu" "0")
          (setq *SC3D_MODEL_LIST* '("Manuel"))
          (SC3D:SET-POPUP-LIST "model" *SC3D_MODEL_LIST* "Manuel")
          (set_tile "fmt" (itoa (SC3D:INDEXOF "1/2.8" *SC3D_SENSOR_LIST*)))
          (set_tile "res" (itoa (SC3D:INDEXOF "1920x1080 (2MP 16:9)" *SC3D_RES_LIST*)))
          (set_tile "std" "0")
          (set_tile "view" "0")
          (set_tile "camname" "")
          (set_tile "situation" "0")
          (set_tile "focal" "5")
          (set_tile "dist" "15")
          (set_tile "camh" "4")
          (set_tile "objh" "2.5")
          (set_tile "grid" "0")
          (set_tile "show_dist" "1")
          (set_tile "trans" "60")
          (set_tile "use_hatch" "0")
          (SC3D:RAND-HATCH)
        )
      )

      (set_tile "hatch_info"
        (strcat "Motif : " *SC3D_CUR_HATCH_PAT* "  Couleur ACI : " (itoa *SC3D_CUR_HATCH_COL*))
      )
      (mode_tile "btn_regen" (if (= (get_tile "use_hatch") "1") 0 1))

      (SC3D:CAM-DLG-APPLY)

      (action_tile "manu" "(SC3D:CAM-DLG-UPDATE-MODELS)")
      (action_tile "model" "(SC3D:CAM-DLG-APPLY)")
      (action_tile "use_hatch" "(SC3D:DLG-HATCH-UPDATE)")
      (action_tile "btn_regen" "(SC3D:DLG-REGEN-HATCH)")
      (action_tile "accept" "(SC3D:ACCEPT-DLG)")
      (action_tile "cancel" "(done_dialog 0)")

      (if (= (start_dialog) 1)
        (setq result SC3D_DLG_RET)
        (setq result nil)
      )

      (unload_dialog id)
      result
    )
  )
)

(defun SC3D:LAYER (name color / ed)
  ;; Creation / mise a jour du calque sans passer par la commande -LAYER.
  (if (tblsearch "LAYER" name)
    (progn
      (setq ed (entget (tblobjname "LAYER" name)))
      (if (assoc 62 ed)
        (setq ed (subst (cons 62 color) (assoc 62 ed) ed))
        (setq ed (append ed (list (cons 62 color))))
      )
      (entmod ed)
    )
    (entmake
      (list
        '(0 . "LAYER")
        '(100 . "AcDbSymbolTableRecord")
        '(100 . "AcDbLayerTableRecord")
        (cons 2 name)
        '(70 . 0)
        (cons 62 color)
        '(6 . "Continuous")
      )
    )
  )
)

(defun SC3D:SAFE-LAYER-NAME (s / bad)
  ;; Nettoie un nom pour pouvoir l'utiliser comme nom de calque.
  (if (or (null s) (= s ""))
    (setq s "CAMERA")
  )
  (setq s (strcase s))
  (setq bad '("<" ">" "/" "\\" "\"" ":" ";" "?" "*" "|" "," "=" "'" "(" ")" "[" "]" "{" "}" "." " "))
  (foreach c bad
    (setq s (SC3D:REPL s c "_"))
  )
  (while (vl-string-search "__" s)
    (setq s (SC3D:REPL s "__" "_"))
  )
  (if (> (strlen s) 180)
    (setq s (substr s 1 180))
  )
  s
)

(defun SC3D:CAMERA-LAYER-NAME (vals / manu model raw)
  ;; Si un modele est choisi, chaque type de camera a son propre calque.
  ;; Exemple : SC3D_CAMERA_HANWHA_VISION_XNO-6083R
  (setq manu (cdr (assoc 'manu vals)))
  (setq model (cdr (assoc 'model vals)))

  (if (and manu model (/= manu "Manuel") (/= model "Manuel"))
    (progn
      (setq raw (strcat manu "_" model))
      (strcat "SC3D_CAMERA_" (SC3D:SAFE-LAYER-NAME raw))
    )
    "SC3D_CAMERA"
  )
)

(defun SC3D:ACTIVE-CAMERA-LAYER ()
  (if (and (boundp '*SC3D_ACTIVE_CAMERA_LAYER*) *SC3D_ACTIVE_CAMERA_LAYER*)
    *SC3D_ACTIVE_CAMERA_LAYER*
    "SC3D_CAMERA"
  )
)

(defun SC3D:CV-LAYER-NAME (vals handle / cvname sit)
  ;; Calque dedie a une camera (une par champ de vision), utilise pour pouvoir
  ;; geler/degeler chaque camera individuellement (cf. VP freeze a l'export) :
  ;; SC3D_<NOM DU CHAMP DE VISION>_<SITUATION> si le champ a un nom, sinon
  ;; SC3D_CV_<handle> (toujours unique, meme sans nom).
  (setq cvname (cdr (assoc 'cvname vals)))
  (setq sit (cdr (assoc 'situation vals)))
  (if (and cvname (/= cvname ""))
    (if (and sit (/= sit ""))
      (strcat "SC3D_" (SC3D:SAFE-LAYER-NAME cvname) "_" sit)
      (strcat "SC3D_" (SC3D:SAFE-LAYER-NAME cvname))
    )
    (strcat "SC3D_CV_" handle)
  )
)

(defun SC3D:CAM-LAYER-ASSIGN (e vals / ed h lay)
  ;; Cree (si besoin) et affecte a la camera e son calque dedie (SC3D:CV-LAYER-NAME).
  ;; Appele a la creation et a la modification (directement), et repris a l'export
  ;; pour rester coherent avec les cameras crees avant l'ajout de ce mecanisme.
  (setq ed (entget e))
  (setq h (cdr (assoc 5 ed)))
  (setq lay (SC3D:CV-LAYER-NAME vals h))
  (SC3D:LAYER lay 2)
  (if (/= (strcase (cdr (assoc 8 ed))) (strcase lay))
    (entmod (subst (cons 8 lay) (assoc 8 ed) ed))
  )
  lay
)


(defun SC3D:SETUP-LAYERS ()
  (SC3D:LAYER "SC3D_GRILLE" 8)
  (SC3D:LAYER "SC3D_CAMERA" 2)
  (SC3D:LAYER "SC3D_RAYONS" 4)
  (SC3D:LAYER "SC3D_AXE" 7)
  (SC3D:LAYER "SC3D_TEXTES" 7)
  (SC3D:LAYER "SC3D_AJUSTEMENT" 30)
  (SC3D:LAYER "SC3D_HACHURE" 3)
  (SC3D:LAYER "SC3D_NON_VISIBLE" 14)
  (SC3D:LAYER "SC3D_PPM_1500" 1)
  (SC3D:LAYER "SC3D_PPM_1000" 6)
  (SC3D:LAYER "SC3D_PPM_500" 211)
  (SC3D:LAYER "SC3D_PPM_250" 15)
  (SC3D:LAYER "SC3D_PPM_125" 2)
  (SC3D:LAYER "SC3D_PPM_80" 3)
  (SC3D:LAYER "SC3D_PPM_62" 3)
  (SC3D:LAYER "SC3D_PPM_40" 4)
  (SC3D:LAYER "SC3D_PPM_25" 4)
  (SC3D:LAYER "SC3D_PPM_20" 132)
  (SC3D:LAYER "SC3D_PPM_12" 5)
  (SC3D:LAYER "SC3D_PPM_2" 195)
)

;; ------------------------------------------------------------------------------------
;; CLIPPING GEOMETRIQUE (remplace XCLIP)
;; ------------------------------------------------------------------------------------

(defun SC3D:CROSS2 (o a b)
  (- (* (- (car a) (car o)) (- (cadr b) (cadr o)))
     (* (- (cadr a) (cadr o)) (- (car b) (car o))))
)

(defun SC3D:LERP-PT (p1 p2 tt / x1 y1 z1 x2 y2 z2)
  (setq x1 (car p1))
  (setq y1 (cadr p1))
  (setq z1 (if (caddr p1) (caddr p1) 0.0))
  (setq x2 (car p2))
  (setq y2 (cadr p2))
  (setq z2 (if (caddr p2) (caddr p2) 0.0))
  (list
    (+ x1 (* tt (- x2 x1)))
    (+ y1 (* tt (- y2 y1)))
    (+ z1 (* tt (- z2 z1)))
  )
)

(defun SC3D:PT-IN-POLY (pt poly / n i j x y xi yi xj yj inside)
  (setq x (car pt))
  (setq y (cadr pt))
  (setq n (length poly))
  (setq inside nil)
  (setq i 0)
  (setq j (- n 1))
  (while (< i n)
    (setq xi (car (nth i poly)))
    (setq yi (cadr (nth i poly)))
    (setq xj (car (nth j poly)))
    (setq yj (cadr (nth j poly)))
    (if (and
          (not (eq (> yi y) (> yj y)))
          (< x (+ xi (/ (* (- xj xi) (- y yi)) (- yj yi))))
        )
      (setq inside (not inside))
    )
    (setq j i)
    (setq i (+ i 1))
  )
  inside
)

(defun SC3D:SEG-INTERSECT-T (p1 p2 q1 q2 / x1 y1 x2 y2 x3 y3 x4 y4 d tt ss)
  ;; Parametre tt (0..1) le long de p1->p2 ou ce segment croise le segment q1->q2.
  ;; nil si pas d'intersection dans les deux segments.
  (setq x1 (car p1)) (setq y1 (cadr p1))
  (setq x2 (car p2)) (setq y2 (cadr p2))
  (setq x3 (car q1)) (setq y3 (cadr q1))
  (setq x4 (car q2)) (setq y4 (cadr q2))
  (setq d (- (* (- x2 x1) (- y4 y3)) (* (- y2 y1) (- x4 x3))))
  (if (equal d 0.0 1e-12)
    nil
    (progn
      (setq tt (/ (- (* (- x3 x1) (- y4 y3)) (* (- y3 y1) (- x4 x3))) d))
      (setq ss (/ (- (* (- x3 x1) (- y2 y1)) (* (- y3 y1) (- x2 x1))) d))
      (if (and (>= tt 0.0) (<= tt 1.0) (>= ss 0.0) (<= ss 1.0))
        tt
        nil
      )
    )
  )
)

(defun SC3D:SORT-DEDUPE (lst / s out prev v)
  (setq s (vl-sort lst '<))
  (setq out '())
  (setq prev nil)
  (foreach v s
    (if (or (null prev) (> (- v prev) 1e-9))
      (setq out (append out (list v)))
    )
    (setq prev v)
  )
  out
)

(defun SC3D:LINE-CLIP-INTERVALS (p1 p2 poly / n i q1 q2 tt ts a b mid midpt result)
  ;; Renvoie la liste des intervalles (a . b), 0<=a<b<=1, ou le segment p1->p2
  ;; (teste en X/Y uniquement) est a l'interieur de poly. Gere les polygones concaves.
  (setq n (length poly))
  (setq ts (list 0.0 1.0))
  (setq i 0)
  (while (< i n)
    (setq q1 (nth i poly))
    (setq q2 (nth (rem (+ i 1) n) poly))
    (setq tt (SC3D:SEG-INTERSECT-T p1 p2 q1 q2))
    (if tt (setq ts (append ts (list tt))))
    (setq i (+ i 1))
  )
  (setq ts (SC3D:SORT-DEDUPE ts))
  (setq result '())
  (setq i 0)
  (while (< i (- (length ts) 1))
    (setq a (nth i ts))
    (setq b (nth (+ i 1) ts))
    (if (> (- b a) 1e-9)
      (progn
        (setq mid (/ (+ a b) 2.0))
        (setq midpt (SC3D:LERP-PT p1 p2 mid))
        (if (SC3D:PT-IN-POLY midpt poly)
          (setq result (append result (list (cons a b))))
        )
      )
    )
    (setq i (+ i 1))
  )
  result
)

(defun SC3D:CLIP-LINE-SEGMENTS (p1 p2 poly / intervals out iv)
  (setq intervals (SC3D:LINE-CLIP-INTERVALS p1 p2 poly))
  (setq out '())
  (foreach iv intervals
    (setq out
      (append out
        (list (list (SC3D:LERP-PT p1 p2 (car iv)) (SC3D:LERP-PT p1 p2 (cdr iv))))
      )
    )
  )
  out
)

(defun SC3D:POLY-SIGNED-AREA2 (pts / n i s p1 p2)
  (setq n (length pts))
  (setq s 0.0)
  (setq i 0)
  (while (< i n)
    (setq p1 (nth i pts))
    (setq p2 (nth (rem (+ i 1) n) pts))
    (setq s (+ s (- (* (car p1) (cadr p2)) (* (car p2) (cadr p1)))))
    (setq i (+ i 1))
  )
  s
)

(defun SC3D:PT-IN-TRI-P (pt a b c / d1 d2 d3 hasNeg hasPos)
  (setq d1 (SC3D:CROSS2 a b pt))
  (setq d2 (SC3D:CROSS2 b c pt))
  (setq d3 (SC3D:CROSS2 c a pt))
  (setq hasNeg (or (< d1 0.0) (< d2 0.0) (< d3 0.0)))
  (setq hasPos (or (> d1 0.0) (> d2 0.0) (> d3 0.0)))
  (not (and hasNeg hasPos))
)

(defun SC3D:EAR-CLIP-TRIANGULATE (poly / idxs n tris i k prevIdx curIdx nextIdx a b c isEar testIdx tp guard sz)
  ;; Triangulation par decoupe d'oreilles (ear clipping) d'un polygone simple,
  ;; convexe ou concave. Ne simplifie jamais les sommets : chaque sommet fourni
  ;; se retrouve comme sommet d'un des triangles renvoyes.
  (setq n (length poly))
  (if (< n 3)
    nil
    (progn
      (setq idxs '())
      (setq i 0)
      (while (< i n)
        (setq idxs (append idxs (list i)))
        (setq i (+ i 1))
      )
      (if (< (SC3D:POLY-SIGNED-AREA2 poly) 0.0)
        (setq idxs (reverse idxs))
      )
      (setq tris '())
      (setq guard 0)
      (while (and (> (length idxs) 3) (< guard 20000))
        (setq sz (length idxs))
        (setq k 0)
        (setq isEar nil)
        (while (and (not isEar) (< k sz))
          (setq prevIdx (nth (rem (+ k (- sz 1)) sz) idxs))
          (setq curIdx  (nth k idxs))
          (setq nextIdx (nth (rem (+ k 1) sz) idxs))
          (setq a (nth prevIdx poly))
          (setq b (nth curIdx poly))
          (setq c (nth nextIdx poly))
          (if (>= (SC3D:CROSS2 a b c) 0.0)
            (progn
              (setq isEar T)
              (foreach testIdx idxs
                (if (and isEar (/= testIdx prevIdx) (/= testIdx curIdx) (/= testIdx nextIdx))
                  (if (SC3D:PT-IN-TRI-P (nth testIdx poly) a b c)
                    (setq isEar nil)
                  )
                )
              )
            )
          )
          (if (not isEar) (setq k (+ k 1)))
        )
        (if isEar
          (progn
            (setq tris (append tris (list (list a b c))))
            (setq idxs (vl-remove curIdx idxs))
          )
          (progn
            ;; Polygone degenere (auto-intersectant) : on decoupe quand meme le
            ;; premier sommet pour ne jamais boucler indefiniment.
            (setq curIdx (car idxs))
            (setq prevIdx (last idxs))
            (setq nextIdx (cadr idxs))
            (setq tris
              (append tris
                (list (list (nth prevIdx poly) (nth curIdx poly) (nth nextIdx poly)))
              )
            )
            (setq idxs (vl-remove curIdx idxs))
          )
        )
        (setq guard (+ guard 1))
      )
      (if (= (length idxs) 3)
        (setq tris
          (append tris
            (list (list (nth (nth 0 idxs) poly) (nth (nth 1 idxs) poly) (nth (nth 2 idxs) poly)))
          )
        )
      )
      tris
    )
  )
)

(defun SC3D:INSIDE-EDGE (p a b)
  (>= (SC3D:CROSS2 a b p) 0.0)
)

(defun SC3D:EDGE-INTERSECT (s e a b / x1 y1 x2 y2 x3 y3 x4 y4 d tt)
  (setq x1 (car s)) (setq y1 (cadr s))
  (setq x2 (car e)) (setq y2 (cadr e))
  (setq x3 (car a))  (setq y3 (cadr a))
  (setq x4 (car b))  (setq y4 (cadr b))
  (setq d (- (* (- x2 x1) (- y4 y3)) (* (- y2 y1) (- x4 x3))))
  (if (equal d 0.0 1e-12)
    e
    (progn
      (setq tt (/ (- (* (- x3 x1) (- y4 y3)) (* (- y3 y1) (- x4 x3))) d))
      (SC3D:LERP-PT s e tt)
    )
  )
)

(defun SC3D:SH-CLIP (subjPts clipPts / output input s e cp1 cp2)
  ;; Sutherland-Hodgman : clipPts doit etre convexe (nos triangles d'oreilles le
  ;; sont toujours), subjPts peut etre quelconque.
  (setq output subjPts)
  (setq cp1 (last clipPts))
  (foreach cp2 clipPts
    (setq input output)
    (setq output '())
    (if input
      (progn
        (setq s (last input))
        (foreach e input
          (if (SC3D:INSIDE-EDGE e cp1 cp2)
            (progn
              (if (not (SC3D:INSIDE-EDGE s cp1 cp2))
                (setq output (append output (list (SC3D:EDGE-INTERSECT s e cp1 cp2))))
              )
              (setq output (append output (list e)))
            )
            (if (SC3D:INSIDE-EDGE s cp1 cp2)
              (setq output (append output (list (SC3D:EDGE-INTERSECT s e cp1 cp2))))
            )
          )
          (setq s e)
        )
      )
    )
    (setq cp1 cp2)
  )
  output
)

(defun SC3D:CLIP-FLAT-POLY (subjPts / frag out tri)
  ;; Decoupe subjPts (polygone plan quelconque) par *SC3D_CLIP_TRIS* (triangulation
  ;; mise en cache du polygone d'ajustement courant). Renvoie une liste de fragments
  ;; convexes (chacun une liste de points).
  (setq out '())
  (foreach tri *SC3D_CLIP_TRIS*
    (setq frag (SC3D:SH-CLIP subjPts tri))
    (if (>= (length frag) 3)
      (setq out (append out (list frag)))
    )
  )
  out
)

(defun SC3D:FAN-TRIANGLES (poly / n i out)
  (setq n (length poly))
  (setq out '())
  (if (>= n 3)
    (progn
      (setq i 1)
      (while (< i (- n 1))
        (setq out (append out (list (list (nth 0 poly) (nth i poly) (nth (+ i 1) poly)))))
        (setq i (+ i 1))
      )
    )
  )
  out
)

(defun SC3D:P (x y z)
  (list x y z)
)

(defun SC3D:PW (x y z / bx by bz ca sa)
  (setq bx (car *SC3D_BASE*))
  (setq by (cadr *SC3D_BASE*))
  (setq bz (caddr *SC3D_BASE*))
  (setq ca *SC3D_CA*)
  (setq sa *SC3D_SA*)
  (list
    (+ bx (- (* x ca) (* y sa)))
    (+ by (+ (* x sa) (* y ca)))
    (+ bz z)
  )
)

(defun SC3D:LINE-RAW (p1 p2 lay col)
  (entmake
    (list
      '(0 . "LINE")
      (cons 8 lay)
      (cons 62 col)
      (cons 10 p1)
      (cons 11 p2)
    )
  )
)

(defun SC3D:LINE (p1 p2 lay col / seg segs)
  (if *SC3D_CLIP_POLY*
    (progn
      (setq segs (SC3D:CLIP-LINE-SEGMENTS p1 p2 *SC3D_CLIP_POLY*))
      (foreach seg segs
        (SC3D:LINE-RAW (nth 0 seg) (nth 1 seg) lay col)
      )
    )
    (SC3D:LINE-RAW p1 p2 lay col)
  )
)

(defun SC3D:DRAW-CLIP-CONTOUR (poly / n i p1 p2)
  ;; Trace le contour orange du polygone d'ajustement courant, non decoupe par
  ;; lui-meme, pour visualiser la limite de la decoupe sur le bloc camera.
  (setq n (length poly))
  (setq i 0)
  (while (< i n)
    (setq p1 (SC3D:P (car (nth i poly)) (cadr (nth i poly)) 0.0))
    (setq p2 (SC3D:P (car (nth (rem (+ i 1) n) poly)) (cadr (nth (rem (+ i 1) n) poly)) 0.0))
    (SC3D:LINE-RAW p1 p2 "SC3D_AJUSTEMENT" 30)
    (setq i (+ i 1))
  )
)

(defun SC3D:ZONE-SOLID-RAW (p1 p2 p3 p4 lay aci rgb trans)
  (entmake
    (list
      '(0 . "SOLID")
      (cons 8 lay)
      (cons 62 aci)
      (cons 420 rgb)
      (cons 440 (SC3D:TRANS-DXF trans))
      (cons 10 p1)
      (cons 11 p2)
      (cons 12 p4)
      (cons 13 p3)
    )
  )
)

(defun SC3D:ZONE-SOLID (p1 p2 p3 p4 lay aci rgb trans / frags frag tri)
  (if *SC3D_CLIP_POLY*
    (progn
      (setq frags (SC3D:CLIP-FLAT-POLY (list p1 p2 p3 p4)))
      (foreach frag frags
        (foreach tri (SC3D:FAN-TRIANGLES frag)
          (SC3D:ZONE-SOLID-RAW
            (nth 0 tri) (nth 1 tri) (nth 2 tri) (nth 2 tri)
            lay aci rgb trans
          )
        )
      )
    )
    (SC3D:ZONE-SOLID-RAW p1 p2 p3 p4 lay aci rgb trans)
  )
)

(defun SC3D:ZONE-HATCH-RAW (pts lay aci rgb trans / npts z midX midY)
  ;; Hachure pleine (motif SOLID) sur un contour plan quelconque (3 sommets ou
  ;; plus) : remplace un SOLID par une vraie entite HATCH.
  (setq npts (length pts))
  (setq z (if (caddr (car pts)) (caddr (car pts)) 0.0))
  (setq midX (/ (apply '+ (mapcar 'car pts)) (float npts)))
  (setq midY (/ (apply '+ (mapcar 'cadr pts)) (float npts)))
  (entmake
    (append
      (list
        '(0 . "HATCH")
        '(100 . "AcDbEntity")
        (cons 8 lay)
        (cons 62 aci)
        (cons 420 rgb)
        (cons 440 (SC3D:TRANS-DXF trans))
        '(100 . "AcDbHatch")
        (list 10 0.0 0.0 z)
        '(210 0.0 0.0 1.0)
        '(2 . "SOLID")
        '(70 . 1)
        '(71 . 0)
        '(91 . 1)
        '(92 . 2)
        '(72 . 0)
        '(73 . 1)
        (cons 93 npts)
      )
      (mapcar '(lambda (pt) (cons 10 (list (car pt) (cadr pt)))) pts)
      (list
        '(75 . 0)
        '(76 . 1)
        '(98 . 1)
        (cons 10 (list midX midY))
      )
    )
  )
)

(defun SC3D:ZONE-HATCH (p1 p2 p3 p4 lay aci rgb trans / frags frag)
  (if *SC3D_CLIP_POLY*
    (progn
      (setq frags (SC3D:CLIP-FLAT-POLY (list p1 p2 p3 p4)))
      (foreach frag frags
        (SC3D:ZONE-HATCH-RAW frag lay aci rgb trans)
      )
    )
    (SC3D:ZONE-HATCH-RAW (list p1 p2 p3 p4) lay aci rgb trans)
  )
)

(defun SC3D:FACE-RAW (p1 p2 p3 p4 lay col)
  (entmake
    (list
      '(0 . "3DFACE")
      (cons 8 lay)
      (cons 62 col)
      (cons 10 p1)
      (cons 11 p2)
      (cons 12 p3)
      (cons 13 p4)
      '(70 . 0)
    )
  )
)

(defun SC3D:TEXT-LOCAL (pt h txt lay col rot)
  (if (and *SC3D_CLIP_POLY* (not (SC3D:PT-IN-POLY pt *SC3D_CLIP_POLY*)))
    nil
    (entmake
      (list
        '(0 . "TEXT")
        (cons 8 lay)
        (cons 62 col)
        (cons 10 pt)
        (cons 40 h)
        (cons 1 txt)
        (cons 50 rot)
        '(7 . "STANDARD")
        '(72 . 1)
        '(73 . 2)
        (cons 11 pt)
      )
    )
  )
)

(defun SC3D:TEXT-WORLD (pt h txt lay col rot / e)
  (setq e
    (entmakex
      (list
        '(0 . "MTEXT")
        '(100 . "AcDbEntity")
        (cons 8 lay)
        (cons 62 col)
        '(100 . "AcDbMText")
        (cons 10 pt)
        (cons 40 h)
        (cons 41 40.0)
        (cons 1 txt)
        (cons 50 rot)
        '(7 . "STANDARD")
        '(71 . 5)
        '(72 . 5)
      )
    )
  )
  e
)

(defun SC3D:CENTER-Z (x camH tilt)
  (- camH (* x (SC3D:TAN tilt)))
)

(defun SC3D:ZTOP (x camH tilt tanV)
  (+ (SC3D:CENTER-Z x camH tilt) (* x tanV))
)

(defun SC3D:ZBOT (x camH tilt tanV)
  (- (SC3D:CENTER-Z x camH tilt) (* x tanV))
)

(defun SC3D:HALF-WIDTH-JVSG (x tanH tilt camH objH / dz depth w)
  (setq dz (- camH objH))
  (setq depth (+ (* x (cos tilt)) (* dz (sin tilt))))
  (setq w (* tanH depth))
  (if (< w 0.0) (- w) w)
)

(defun SC3D:FULL-WIDTH-JVSG (x tanH tilt camH objH)
  (* 2.0 (SC3D:HALF-WIDTH-JVSG x tanH tilt camH objH))
)

(defun SC3D:CONE-HALF-WIDTH (x maxD tanH tilt camH objH / wMax wCone wJvsg)
  (if (<= maxD 0.0)
    0.0
    (progn
      (setq wMax (SC3D:HALF-WIDTH-JVSG maxD tanH tilt camH objH))
      (setq wCone (* wMax (/ x maxD)))
      (setq wJvsg (SC3D:HALF-WIDTH-JVSG x tanH tilt camH objH))
      (SC3D:MIN wJvsg wCone)
    )
  )
)

(defun SC3D:GROUND-BAND (x1 x2 maxD tanH tilt camH objH lay aci rgb trans hatch / w1 w2 p1 p2 p3 p4 e1 e2 e3 e4)
  (if (> x2 x1)
    (progn
      (setq w1 (SC3D:CONE-HALF-WIDTH x1 maxD tanH tilt camH objH))
      (setq w2 (SC3D:CONE-HALF-WIDTH x2 maxD tanH tilt camH objH))

      (setq p1 (SC3D:P x1 (- w1) *SC3D_PPM_SOLID_Z*))
      (setq p2 (SC3D:P x1 w1 *SC3D_PPM_SOLID_Z*))
      (setq p3 (SC3D:P x2 w2 *SC3D_PPM_SOLID_Z*))
      (setq p4 (SC3D:P x2 (- w2) *SC3D_PPM_SOLID_Z*))

      (setq e1 (SC3D:P x1 (- w1) *SC3D_PPM_EDGE_Z*))
      (setq e2 (SC3D:P x1 w1 *SC3D_PPM_EDGE_Z*))
      (setq e3 (SC3D:P x2 w2 *SC3D_PPM_EDGE_Z*))
      (setq e4 (SC3D:P x2 (- w2) *SC3D_PPM_EDGE_Z*))

      (if hatch
        (SC3D:ZONE-HATCH p1 p2 p3 p4 lay aci rgb trans)
        (SC3D:ZONE-SOLID p1 p2 p3 p4 lay aci rgb trans)
      )

      (SC3D:LINE e1 e2 lay aci)
      (SC3D:LINE e2 e3 lay aci)
      (SC3D:LINE e3 e4 lay aci)
      (SC3D:LINE e4 e1 lay aci)
    )
  )
)

(defun SC3D:VERT-RECT (x maxD tanH tilt camH objH hObj lay col / w p1 p2 p3 p4 intervals iv b1 b2 q1 q2 q3 q4)
  (setq w (SC3D:CONE-HALF-WIDTH x maxD tanH tilt camH objH))
  (setq p1 (SC3D:P x (- w) 0.0))
  (setq p2 (SC3D:P x w 0.0))
  (setq p3 (SC3D:P x w hObj))
  (setq p4 (SC3D:P x (- w) hObj))
  (if *SC3D_CLIP_POLY*
    (progn
      ;; Ce rectangle est un "mur" vertical a X constant : sa projection en X/Y est
      ;; le segment p1-p2, donc on reutilise le clip de ligne pour trouver les
      ;; intervalles Y visibles, puis on reconstruit un sous-mur par intervalle.
      (setq intervals (SC3D:LINE-CLIP-INTERVALS p1 p2 *SC3D_CLIP_POLY*))
      (foreach iv intervals
        (setq b1 (SC3D:LERP-PT p1 p2 (car iv)))
        (setq b2 (SC3D:LERP-PT p1 p2 (cdr iv)))
        (setq q1 (SC3D:P x (cadr b1) 0.0))
        (setq q2 (SC3D:P x (cadr b2) 0.0))
        (setq q3 (SC3D:P x (cadr b2) hObj))
        (setq q4 (SC3D:P x (cadr b1) hObj))
        (SC3D:FACE-RAW q1 q2 q3 q4 lay col)
        (SC3D:LINE-RAW q1 q2 lay col)
        (SC3D:LINE-RAW q3 q4 lay col)
      )
    )
    (progn
      (SC3D:FACE-RAW p1 p2 p3 p4 lay col)
      (SC3D:LINE-RAW p1 p2 lay col)
      (SC3D:LINE-RAW p3 p4 lay col)
    )
  )
)

(defun SC3D:GRID (maxD tanH tilt camH objH / i yMax)
  (setq yMax (+ 2.0 (SC3D:HALF-WIDTH-JVSG maxD tanH tilt camH objH)))
  (setq i 0.0)
  (while (<= i maxD)
    (SC3D:LINE (SC3D:P i (- yMax) 0.0) (SC3D:P i yMax 0.0) "SC3D_GRILLE" 8)
    (setq i (+ i 1.0))
  )
  (setq i (- (fix yMax)))
  (while (<= i yMax)
    (SC3D:LINE (SC3D:P 0.0 i 0.0) (SC3D:P maxD i 0.0) "SC3D_GRILLE" 8)
    (setq i (+ i 1.0))
  )
)

(defun SC3D:CAMERA-SYMBOL (camH / s lay)
  (setq s 0.35)
  (setq lay (SC3D:ACTIVE-CAMERA-LAYER))
  (SC3D:LINE (SC3D:P (- s) (- s) camH) (SC3D:P s (- s) camH) lay 2)
  (SC3D:LINE (SC3D:P s (- s) camH) (SC3D:P s s camH) lay 2)
  (SC3D:LINE (SC3D:P s s camH) (SC3D:P (- s) s camH) lay 2)
  (SC3D:LINE (SC3D:P (- s) s camH) (SC3D:P (- s) (- s) camH) lay 2)
)

(defun SC3D:DRAW-FRUSTUM (maxD camH objH tilt tanH tanV / w zc zt zb)
  (setq w  (SC3D:HALF-WIDTH-JVSG maxD tanH tilt camH objH))
  (setq zc (SC3D:CENTER-Z maxD camH tilt))
  (setq zt (SC3D:ZTOP maxD camH tilt tanV))
  (setq zb (SC3D:ZBOT maxD camH tilt tanV))

  (SC3D:LINE (SC3D:P 0.0 0.0 camH) (SC3D:P maxD (- w) zt) "SC3D_RAYONS" 4)
  (SC3D:LINE (SC3D:P 0.0 0.0 camH) (SC3D:P maxD w zt) "SC3D_RAYONS" 4)
  (SC3D:LINE (SC3D:P 0.0 0.0 camH) (SC3D:P maxD (- w) zb) "SC3D_RAYONS" 4)
  (SC3D:LINE (SC3D:P 0.0 0.0 camH) (SC3D:P maxD w zb) "SC3D_RAYONS" 4)

  (SC3D:LINE (SC3D:P maxD (- w) zt) (SC3D:P maxD w zt) "SC3D_RAYONS" 4)
  (SC3D:LINE (SC3D:P maxD w zt) (SC3D:P maxD w zb) "SC3D_RAYONS" 4)
  (SC3D:LINE (SC3D:P maxD w zb) (SC3D:P maxD (- w) zb) "SC3D_RAYONS" 4)
  (SC3D:LINE (SC3D:P maxD (- w) zb) (SC3D:P maxD (- w) zt) "SC3D_RAYONS" 4)

  (SC3D:LINE (SC3D:P 0.0 0.0 camH) (SC3D:P maxD 0.0 zc) "SC3D_AXE" 7)
)

(defun SC3D:DRAW-DIST-LABELS (maxD / d)
  (setq d 5.0)
  (while (<= d maxD)
    (SC3D:LINE (SC3D:P d -0.25 0.02) (SC3D:P d 0.25 0.02) "SC3D_TEXTES" 30)
    (SC3D:TEXT-LOCAL (SC3D:P d 0.55 0.05) 0.25 (strcat (rtos d 2 0) "m") "SC3D_TEXTES" 30 0.0)
    (setq d (+ d 5.0))
  )
)

(defun SC3D:CORNER-X-PLANE (x tanH tanV tilt signV / den)
  ;; Coordonne X d'un coin du CDV sur le plan vertical situe a la distance x.
  ;; signV =  1 : coin haut
  ;; signV = -1 : coin bas
  (setq den (+ (cos tilt) (* signV tanV (sin tilt))))
  (if (equal den 0.0 0.000000001)
    0.0
    (/ (* x tanH) den)
  )
)

(defun SC3D:CORNER-Z-PLANE (x tanV tilt camH signV / den num)
  ;; Coordonne Z d'un coin du CDV sur le plan vertical situe a la distance x.
  (setq den (+ (cos tilt) (* signV tanV (sin tilt))))
  (setq num (- (* signV tanV (cos tilt)) (sin tilt)))
  (if (equal den 0.0 0.000000001)
    camH
    (+ camH (/ (* x num) den))
  )
)

(defun SC3D:FULL-WIDTH-JVSG-PPM (x tanH tanV tilt camH objH / xt zt xb zb k xg w1 w2)
  ;; JVSG n'utilise pas exactement la largeur CDV affichee pour le PPM.
  ;; Pour le PPM, si le bas du champ passe sous le sol, il prend la largeur
  ;; au croisement sol des deux aretes verticales gauche/droite du volume.
  (if (<= x 0.0)
    0.0
    (progn
      (setq xt (SC3D:CORNER-X-PLANE x tanH tanV tilt 1.0))
      (setq zt (SC3D:CORNER-Z-PLANE x tanV tilt camH 1.0))
      (setq xb (SC3D:CORNER-X-PLANE x tanH tanV tilt -1.0))
      (setq zb (SC3D:CORNER-Z-PLANE x tanV tilt camH -1.0))

      (if (and (not (equal zb zt 0.000000001))
               (or (and (> zt 0.0) (< zb 0.0))
                   (and (< zt 0.0) (> zb 0.0))))
        (progn
          (setq k (/ (- 0.0 zt) (- zb zt)))
          (setq xg (+ xt (* k (- xb xt))))
          (* 2.0 (abs xg))
        )
        (progn
          (setq w1 (abs xt))
          (setq w2 (abs xb))
          (* 2.0 (SC3D:MIN w1 w2))
        )
      )
    )
  )
)

(defun SC3D:PPM-DIST (ppm resW tanH tanV tilt camH objH maxD / targetWidth lo hi mid w i)
  ;; Distance ou le PPM atteint le seuil demande.
  ;; Recherche numerique car JVSG change de largeur de reference pour le PPM
  ;; quand le champ traverse le sol.
  (setq targetWidth (/ resW ppm))

  (if (<= targetWidth 0.0)
    0.0
    (progn
      (if (<= (SC3D:FULL-WIDTH-JVSG-PPM maxD tanH tanV tilt camH objH) targetWidth)
        (+ maxD 1.0)
        (progn
          (setq lo 0.0)
          (setq hi maxD)
          (setq i 0)

          (while (< i 45)
            (setq mid (/ (+ lo hi) 2.0))
            (setq w (SC3D:FULL-WIDTH-JVSG-PPM mid tanH tanV tilt camH objH))
            (if (< w targetWidth)
              (setq lo mid)
              (setq hi mid)
            )
            (setq i (+ i 1))
          )

          hi
        )
      )
    )
  )
)

(defun SC3D:PPM-DIST-TOP-OLD (ppm resW tanH tilt camH objH / targetWidth halfWidth dz d)
  ;; Ancien calcul conserve pour la vue du dessus.
  ;; Il remet les limites des blocs PPM comme avant, sans toucher au calcul PPM par distance.
  (setq targetWidth (/ resW ppm))
  (setq halfWidth (/ targetWidth 2.0))
  (setq dz (- camH objH))
  (setq d (/ (- (/ halfWidth tanH) (* dz (sin tilt))) (cos tilt)))
  (if (< d 0.0) 0.0 d)
)

(defun SC3D:PPM-LIST (standard)
  (if (= standard "2025")
    (list
      (list 1500.0 "SC3D_PPM_1500" 1 (SC3D:RGB 255 55 65))
      (list 500.0  "SC3D_PPM_500"  6 (SC3D:RGB 245 95 175))
      (list 250.0  "SC3D_PPM_250"  1 (SC3D:RGB 255 125 135))
      (list 125.0  "SC3D_PPM_125"  2 (SC3D:RGB 255 235 85))
      (list 80.0   "SC3D_PPM_80"   3 (SC3D:RGB 125 255 105))
      (list 40.0   "SC3D_PPM_40"   4 (SC3D:RGB 85 220 230))
      (list 20.0   "SC3D_PPM_20"   5 (SC3D:RGB 95 145 235))
      ;; Zone supplementaire 20 a 2 PPM.
      (list 2.0    "SC3D_PPM_2"    9 (SC3D:RGB 160 90 220))
    )
    (list
      (list 1000.0 "SC3D_PPM_1000" 6 (SC3D:RGB 255 0 130))
      (list 250.0  "SC3D_PPM_250"  1 (SC3D:RGB 255 0 0))
      (list 125.0  "SC3D_PPM_125"  2 (SC3D:RGB 255 255 0))
      (list 62.0   "SC3D_PPM_62"   3 (SC3D:RGB 0 255 0))
      (list 25.0   "SC3D_PPM_25"   4 (SC3D:RGB 0 255 255))
      (list 12.0   "SC3D_PPM_12"   5 (SC3D:RGB 0 95 255))
      ;; Zone supplementaire 12 a 2 PPM.
      (list 2.0    "SC3D_PPM_2"    9 (SC3D:RGB 160 90 220))
    )
  )
)

(defun SC3D:DRAW-PPM (resW maxD nearD tanH tanV tilt camH objH standard trans / lst prev done z ppm lay aci rgb d x1 x2)
  (setq lst (SC3D:PPM-LIST standard))
  (setq prev 0.0)
  (setq done nil)

  (foreach z lst
    (if (not done)
      (progn
        (setq ppm (nth 0 z))
        (setq lay (nth 1 z))
        (setq aci (nth 2 z))
        (setq rgb (nth 3 z))
        (setq d (SC3D:PPM-DIST-TOP-OLD ppm resW tanH tilt camH objH))
        (setq x1 (SC3D:MAX prev nearD))
        (setq x2 (SC3D:MIN d maxD))

        (if (> x2 x1)
          (SC3D:GROUND-BAND x1 x2 maxD tanH tilt camH objH lay aci rgb trans T)
        )

        (if (and (> d nearD) (<= d maxD))
          (SC3D:VERT-RECT d maxD tanH tilt camH objH objH lay aci)
        )

        (if (>= d maxD)
          (setq done T)
          (setq prev d)
        )
      )
    )
  )
)

(defun SC3D:CAMERA-ANGLE-INTERP (focal fmin fmax angWide angTele / coef tanWide tanTele tanA)
  (if (and (> focal 0.0) (> fmin 0.0) (> fmax 0.0) (> angWide 0.0) (> angTele 0.0) (/= fmin fmax))
    (progn
      (setq coef (/ (- (/ 1.0 focal) (/ 1.0 fmax)) (- (/ 1.0 fmin) (/ 1.0 fmax))))
      (if (< coef 0.0) (setq coef 0.0))
      (if (> coef 1.0) (setq coef 1.0))
      (setq tanWide (SC3D:TAN (/ (SC3D:DTR angWide) 2.0)))
      (setq tanTele (SC3D:TAN (/ (SC3D:DTR angTele) 2.0)))
      (setq tanA (+ tanTele (* coef (- tanWide tanTele))))
      (SC3D:RTD (* 2.0 (atan tanA)))
    )
    nil
  )
)

(defun SC3D:CAMERA-HANGLE (vals focal / manu model cam fmin fmax hmax hmin)
  (setq manu (cdr (assoc 'manu vals)))
  (setq model (cdr (assoc 'model vals)))
  (if (and manu model (/= manu "Manuel") (/= model "Manuel"))
    (progn
      (setq cam (SC3D:FIND-CAMERA manu model))
      (if cam
        (progn
          (setq fmin (cdr (assoc 'fmin cam)))
          (setq fmax (cdr (assoc 'fmax cam)))
          (setq hmax (cdr (assoc 'hmax cam)))
          (setq hmin (cdr (assoc 'hmin cam)))
          (SC3D:CAMERA-ANGLE-INTERP focal fmin fmax hmax hmin)
        )
        nil
      )
    )
    nil
  )
)

(defun SC3D:CAMERA-VANGLE (vals focal / manu model cam fmin fmax vmax vmin)
  (setq manu (cdr (assoc 'manu vals)))
  (setq model (cdr (assoc 'model vals)))
  (if (and manu model (/= manu "Manuel") (/= model "Manuel"))
    (progn
      (setq cam (SC3D:FIND-CAMERA manu model))
      (if cam
        (progn
          (setq fmin (cdr (assoc 'fmin cam)))
          (setq fmax (cdr (assoc 'fmax cam)))
          (setq vmax (cdr (assoc 'vmax cam)))
          (setq vmin (cdr (assoc 'vmin cam)))
          (SC3D:CAMERA-ANGLE-INTERP focal fmin fmax vmax vmin)
        )
        nil
      )
    )
    nil
  )
)

(defun SC3D:CALC (vals / fmt focal resStr res resW resH aspect sw sh hAng vAng hHalf vHalf tanH tanV maxD camH objH tilt nearD targetWidthMax hAngCam vAngCam)
  (setq fmt    (cdr (assoc 'fmt vals)))
  (setq focal  (cdr (assoc 'focal vals)))
  (setq resStr (cdr (assoc 'res vals)))
  (setq maxD   (cdr (assoc 'dist vals)))
  (setq camH   (cdr (assoc 'camh vals)))
  (setq objH   (cdr (assoc 'objh vals)))

  (setq res (SC3D:PARSE-RES resStr))
  (setq resW (float (car res)))
  (setq resH (float (cadr res)))
  (setq aspect (/ resW resH))

  (setq sw (SC3D:SENSOR-WIDTH fmt))
  (setq sh (/ sw aspect))

  (setq hAngCam (SC3D:CAMERA-HANGLE vals focal))
  (setq vAngCam (SC3D:CAMERA-VANGLE vals focal))

  (if hAngCam
    (setq hAng hAngCam)
    (setq hAng (SC3D:RTD (* 2.0 (atan (/ sw (* 2.0 focal))))))
  )

  (if vAngCam
    (setq vAng vAngCam)
    (setq vAng (SC3D:RTD (* 2.0 (atan (/ sh (* 2.0 focal))))))
  )

  (setq hHalf (/ (SC3D:DTR hAng) 2.0))
  (setq vHalf (/ (SC3D:DTR vAng) 2.0))
  (setq tanH (SC3D:TAN hHalf))
  (setq tanV (SC3D:TAN vHalf))

  (setq tilt (+ (atan (/ (- camH objH) maxD)) vHalf))
  (setq nearD (/ camH (SC3D:TAN (+ tilt vHalf))))
  (setq targetWidthMax (SC3D:FULL-WIDTH-JVSG maxD tanH tilt camH objH))

  (list
    (cons 'resW resW)
    (cons 'resH resH)
    (cons 'sw sw)
    (cons 'tanH tanH)
    (cons 'tanV tanV)
    (cons 'tilt tilt)
    (cons 'nearD nearD)
    (cons 'targetWidthMax targetWidthMax)
    (cons 'hAng hAng)
    (cons 'vAng vAng)
  )
)

(defun SC3D:EMIT-HATCH (pts patName aci / npts midX)
  (setq npts (length pts))
  (setq midX (/ (apply '+ (mapcar 'car pts)) (float npts)))

  (entmake
    (append
      (list
        '(0 . "HATCH")
        '(100 . "AcDbEntity")
        (cons 8 "SC3D_HACHURE")
        (cons 62 aci)
        '(100 . "AcDbHatch")
        '(10 0.0 0.0 0.0)
        '(210 0.0 0.0 1.0)
        (cons 2 patName)
        '(70 . 0)
        '(71 . 0)
        '(91 . 1)
        '(92 . 2)
        '(72 . 0)
        '(73 . 1)
        (cons 93 npts)
      )
      (mapcar '(lambda (pt) (cons 10 (list (car pt) (cadr pt)))) pts)
      (list
        '(75 . 0)
        '(76 . 1)
        '(52 . 0.0)
        '(41 . 0.20)
        '(47 . 1.0)
        '(98 . 1)
        (cons 10 (list midX 0.0))
      )
    )
  )
)

(defun SC3D:DRAW-HATCH-FOV (maxD nearD tanH tilt camH objH patName aci / wMax w1 pts frags frag)
  (setq wMax (SC3D:HALF-WIDTH-JVSG maxD tanH tilt camH objH))

  (if (<= nearD 0.0)
    (setq pts
      (list
        (list 0.0 0.0)
        (list maxD (- wMax))
        (list maxD wMax)
      )
    )
    (progn
      (setq w1 (SC3D:CONE-HALF-WIDTH nearD maxD tanH tilt camH objH))
      (setq pts
        (list
          (list nearD (- w1))
          (list nearD w1)
          (list maxD wMax)
          (list maxD (- wMax))
        )
      )
    )
  )

  (if *SC3D_CLIP_POLY*
    (progn
      (setq frags (SC3D:CLIP-FLAT-POLY pts))
      (foreach frag frags
        (SC3D:EMIT-HATCH frag patName aci)
      )
    )
    (SC3D:EMIT-HATCH pts patName aci)
  )
)

(defun SC3D:CREATE-BLOCK-GEOM (blockName vals calc / maxD camH objH standard showGrid trans resW tanH tanV tilt nearD useHatch hatchPat hatchCol hidden showDist)
  (setq maxD     (cdr (assoc 'dist vals)))
  (setq camH     (cdr (assoc 'camh vals)))
  (setq objH     (cdr (assoc 'objh vals)))
  (setq standard (cdr (assoc 'std vals)))
  (setq showGrid (cdr (assoc 'grid vals)))
  (setq trans    (cdr (assoc 'trans vals)))
  (setq resW     (cdr (assoc 'resW calc)))
  (setq tanH     (cdr (assoc 'tanH calc)))
  (setq tanV     (cdr (assoc 'tanV calc)))
  (setq tilt     (cdr (assoc 'tilt calc)))
  (setq nearD    (cdr (assoc 'nearD calc)))
  (setq useHatch (cdr (assoc 'use_hatch vals)))
  (setq hatchPat (cdr (assoc 'hatch_pattern vals)))
  (setq hatchCol (cdr (assoc 'hatch_color vals)))
  (setq hidden   (cdr (assoc 'hidden vals)))
  ;; Absent (anciennes configs) = affiche par defaut.
  (setq showDist (if (assoc 'show_dist vals) (cdr (assoc 'show_dist vals)) T))

  (if (null hatchPat) (setq hatchPat "ANSI31"))
  (if (null hatchCol) (setq hatchCol 1))

  (if (< trans 0.0) (setq trans 0.0))
  (if (> trans 90.0) (setq trans 90.0))

  (entmake (list '(0 . "BLOCK") (cons 2 blockName) '(70 . 0) '(10 0.0 0.0 0.0)))

  (if hidden
    ;; Camera masquee : seule la zone non visible (angle mort pres de la camera) reste affichee.
    (if (> nearD 0.0)
      (SC3D:GROUND-BAND
        0.0
        (SC3D:MIN nearD maxD)
        maxD
        tanH
        tilt
        camH
        objH
        "SC3D_NON_VISIBLE"
        1
        (SC3D:RGB 120 0 0)
        trans
        T
      )
    )
    (progn
      (if (> nearD 0.0)
        (SC3D:GROUND-BAND
          0.0
          (SC3D:MIN nearD maxD)
          maxD
          tanH
          tilt
          camH
          objH
          "SC3D_NON_VISIBLE"
          1
          (SC3D:RGB 120 0 0)
          trans
          T
        )
      )

      (SC3D:DRAW-PPM resW maxD nearD tanH tanV tilt camH objH standard trans)

      (if useHatch
        (SC3D:DRAW-HATCH-FOV maxD nearD tanH tilt camH objH hatchPat hatchCol)
      )

      (if showGrid
        (SC3D:GRID maxD tanH tilt camH objH)
      )

      (SC3D:CAMERA-SYMBOL camH)
      (SC3D:DRAW-FRUSTUM maxD camH objH tilt tanH tanV)
      (if showDist
        (SC3D:DRAW-DIST-LABELS maxD)
      )
      (SC3D:VERT-RECT maxD maxD tanH tilt camH objH objH "SC3D_RAYONS" 4)

      (if *SC3D_CLIP_POLY*
        (SC3D:DRAW-CLIP-CONTOUR *SC3D_CLIP_POLY*)
      )
    )
  )

  (entmake '((0 . "ENDBLK")))
)

;; ------------------------------------------------------------------------------------
;; VUE DE COTE
;; x = distance depuis la camera, y = hauteur, z = 0.
;; Cette vue reprend les memes calculs que la vue du dessus, mais elle affiche le profil
;; vertical : hauteur camera, rayon haut, rayon bas, zone non visible et zones PPM.
;; ------------------------------------------------------------------------------------

(defun SC3D:SIDE-RAY-Y (x camH angle)
  (- camH (* x (SC3D:TAN angle)))
)

(defun SC3D:SIDE-TOP-Y (x camH tilt vHalf)
  (SC3D:SIDE-RAY-Y x camH (- tilt vHalf))
)

(defun SC3D:SIDE-CENTER-Y (x camH tilt)
  (SC3D:SIDE-RAY-Y x camH tilt)
)

(defun SC3D:SIDE-BOT-Y (x camH tilt vHalf)
  (SC3D:SIDE-RAY-Y x camH (+ tilt vHalf))
)

(defun SC3D:SIDE-P (x y)
  (SC3D:P x y 0.0)
)

(defun SC3D:SIDE-BAND (x1 x2 h lay aci rgb trans hatch / p1 p2 p3 p4)
  (if (< x1 0.0) (setq x1 0.0))
  (if (< x2 0.0) (setq x2 0.0))
  (if (< h 0.0) (setq h 0.0))

  (if (> x2 x1)
    (progn
      (setq p1 (SC3D:SIDE-P x1 0.0))
      (setq p2 (SC3D:SIDE-P x2 0.0))
      (setq p3 (SC3D:SIDE-P x2 h))
      (setq p4 (SC3D:SIDE-P x1 h))

      (if hatch
        (SC3D:ZONE-HATCH p1 p2 p3 p4 lay aci rgb trans)
        (SC3D:ZONE-SOLID p1 p2 p3 p4 lay aci rgb trans)
      )
      (SC3D:LINE p1 p2 lay aci)
      (SC3D:LINE p2 p3 lay aci)
      (SC3D:LINE p3 p4 lay aci)
      (SC3D:LINE p4 p1 lay aci)
    )
  )
)

(defun SC3D:SIDE-DRAW-PPM (resW maxD nearD tanH tanV tilt camH objH standard trans / lst prev done z ppm lay aci rgb d x1 x2)
  (setq lst (SC3D:PPM-LIST standard))
  (setq prev 0.0)
  (setq done nil)

  (foreach z lst
    (if (not done)
      (progn
        (setq ppm (nth 0 z))
        (setq lay (nth 1 z))
        (setq aci (nth 2 z))
        (setq rgb (nth 3 z))
        (setq d (SC3D:PPM-DIST ppm resW tanH tanV tilt camH objH maxD))
        (setq x1 (SC3D:MAX prev nearD))
        (setq x2 (SC3D:MIN d maxD))

        (if (> x2 x1)
          (SC3D:SIDE-BAND x1 x2 objH lay aci rgb trans T)
        )

        (if (>= d maxD)
          (setq done T)
          (setq prev d)
        )
      )
    )
  )
)

(defun SC3D:SIDE-GRID (maxD camH objH tilt vHalf / yMax yTop i)
  (setq yMax (SC3D:SIDE-YMAX maxD camH objH tilt vHalf))

  (setq i 0.0)
  (while (<= i maxD)
    (SC3D:LINE (SC3D:SIDE-P i 0.0) (SC3D:SIDE-P i yMax) "SC3D_GRILLE" 8)
    (setq i (+ i 1.0))
  )

  (setq i 0.0)
  (while (<= i yMax)
    (SC3D:LINE (SC3D:SIDE-P 0.0 i) (SC3D:SIDE-P maxD i) "SC3D_GRILLE" 8)
    (setq i (+ i 1.0))
  )
)

(defun SC3D:SIDE-CAM-PT (camH tilt dx dy / ca sa x y)
  ;; dx = avance dans le sens de la camera, dy = hauteur locale du symbole.
  ;; En vue de cote, un tilt positif pointe vers le bas.
  (setq ca (cos tilt))
  (setq sa (sin tilt))
  (setq x (+ (* dx ca) (* dy sa)))
  (setq y (+ camH (- (* dy ca) (* dx sa))))
  (SC3D:SIDE-P x y)
)

(defun SC3D:SIDE-CAMERA-SYMBOL (camH tilt / l h lay p1 p2 p3 p4)
  (setq l 0.55)
  (setq h 0.34)
  (setq lay (SC3D:ACTIVE-CAMERA-LAYER))

  ;; Symbole camera incline selon l'axe optique reel de la vue de cote.
  (setq p1 (SC3D:SIDE-CAM-PT camH tilt (- (/ l 2.0)) (- (/ h 2.0))))
  (setq p2 (SC3D:SIDE-CAM-PT camH tilt (/ l 2.0) (- (/ h 2.0))))
  (setq p3 (SC3D:SIDE-CAM-PT camH tilt (/ l 2.0) (/ h 2.0)))
  (setq p4 (SC3D:SIDE-CAM-PT camH tilt (- (/ l 2.0)) (/ h 2.0)))

  (SC3D:LINE p1 p2 lay 2)
  (SC3D:LINE p2 p3 lay 2)
  (SC3D:LINE p3 p4 lay 2)
  (SC3D:LINE p4 p1 lay 2)
)

(defun SC3D:SIDE-YMAX (maxD camH objH tilt vHalf / yTop yMax)
  (setq yTop (SC3D:SIDE-TOP-Y maxD camH tilt vHalf))
  (setq yMax (+ 1.0 (SC3D:MAX camH (SC3D:MAX objH yTop))))
  (if (< yMax 5.0) (setq yMax 5.0))
  yMax
)

(defun SC3D:SIDE-DRAW-AXES (maxD camH objH tilt vHalf / y)
  ;; Axe distance au sol
  (SC3D:LINE (SC3D:SIDE-P 0.0 0.0) (SC3D:SIDE-P maxD 0.0) "SC3D_AXE" 7)

  ;; Axe hauteur : ne depasse pas la hauteur de la camera
  (SC3D:LINE (SC3D:SIDE-P 0.0 0.0) (SC3D:SIDE-P 0.0 camH) "SC3D_AXE" 7)

  ;; Reperes de hauteur : pas de texte 0 sur l'axe hauteur
  (setq y 0.0)
  (while (<= y camH)
    (SC3D:LINE (SC3D:SIDE-P -0.12 y) (SC3D:SIDE-P 0.12 y) "SC3D_AXE" 7)
    (if (and (> y 0.0) (= (rem (fix y) 5) 0))
      (SC3D:TEXT-LOCAL (SC3D:SIDE-P -0.55 y) 0.25 (rtos y 2 0) "SC3D_TEXTES" 7 0.0)
    )
    (setq y (+ y 1.0))
  )
)

(defun SC3D:SIDE-DIST-LABELS (maxD camH objH / d yMax)
  (setq yMax (+ camH 0.70))
  (setq d 0.0)
  (while (<= d maxD)
    (SC3D:LINE (SC3D:SIDE-P d -0.12) (SC3D:SIDE-P d 0.12) "SC3D_AXE" 7)
    (if (or (= d 0.0) (= (rem (fix d) 5) 0))
      (SC3D:TEXT-LOCAL (SC3D:SIDE-P d -0.45) 0.25 (rtos d 2 0) "SC3D_TEXTES" 30 0.0)
    )
    (setq d (+ d 1.0))
  )

  (SC3D:TEXT-LOCAL (SC3D:SIDE-P -0.75 camH) 0.25 (strcat (rtos camH 2 2) "m") "SC3D_TEXTES" 7 0.0)
  (SC3D:TEXT-LOCAL (SC3D:SIDE-P (+ maxD 0.55) objH) 0.25 (strcat (rtos objH 2 2) "m") "SC3D_TEXTES" 7 0.0)
)

(defun SC3D:SIDE-DRAW-FRUSTUM (maxD camH objH tilt vHalf nearD / topY centerY botX botY angleDeg)
  (setq topY    (SC3D:SIDE-TOP-Y maxD camH tilt vHalf))
  (setq centerY (SC3D:SIDE-CENTER-Y maxD camH tilt))
  (setq botX    (SC3D:MIN nearD maxD))
  (setq botY    (SC3D:SIDE-BOT-Y botX camH tilt vHalf))
  (if (< botY 0.0) (setq botY 0.0))

  ;; Le sol est dessine par l'axe distance (SC3D_AXE).

  ;; Rayon haut du champ de vision.
  (SC3D:LINE (SC3D:SIDE-P 0.0 camH) (SC3D:SIDE-P maxD topY) "SC3D_RAYONS" 4)

  ;; Rayon bas du champ de vision.
  (SC3D:LINE (SC3D:SIDE-P 0.0 camH) (SC3D:SIDE-P botX botY) "SC3D_RAYONS" 4)

  ;; Cible a la distance max
  (SC3D:LINE (SC3D:SIDE-P maxD 0.0) (SC3D:SIDE-P maxD objH) "SC3D_RAYONS" 1)

  ;; Petit repere orange en haut de cible
  (SC3D:LINE (SC3D:SIDE-P (- maxD 0.12) objH) (SC3D:SIDE-P (+ maxD 0.12) objH) "SC3D_TEXTES" 30)
  (SC3D:LINE (SC3D:SIDE-P maxD (- objH 0.12)) (SC3D:SIDE-P maxD (+ objH 0.12)) "SC3D_TEXTES" 30)

  (setq angleDeg (SC3D:RTD tilt))
  (SC3D:TEXT-LOCAL (SC3D:SIDE-P 0.65 (+ camH 0.45)) 0.25 (strcat (rtos angleDeg 2 1) "°") "SC3D_TEXTES" 2 0.0)
)

(defun SC3D:CREATE-BLOCK-GEOM-SIDE (blockName vals calc / maxD camH objH standard showGrid trans resW tanH tanV tilt nearD vHalf hidden showDist)
  (setq maxD     (cdr (assoc 'dist vals)))
  (setq camH     (cdr (assoc 'camh vals)))
  (setq objH     (cdr (assoc 'objh vals)))
  (setq standard (cdr (assoc 'std vals)))
  (setq showGrid (cdr (assoc 'grid vals)))
  (setq trans    (cdr (assoc 'trans vals)))
  (setq resW     (cdr (assoc 'resW calc)))
  (setq tanH     (cdr (assoc 'tanH calc)))
  (setq tanV     (cdr (assoc 'tanV calc)))
  (setq tilt     (cdr (assoc 'tilt calc)))
  (setq nearD    (cdr (assoc 'nearD calc)))
  (setq vHalf    (/ (SC3D:DTR (cdr (assoc 'vAng calc))) 2.0))
  (setq hidden   (cdr (assoc 'hidden vals)))
  ;; Absent (anciennes configs) = affiche par defaut.
  (setq showDist (if (assoc 'show_dist vals) (cdr (assoc 'show_dist vals)) T))

  (if (< trans 0.0) (setq trans 0.0))
  (if (> trans 90.0) (setq trans 90.0))

  (entmake (list '(0 . "BLOCK") (cons 2 blockName) '(70 . 0) '(10 0.0 0.0 0.0)))

  (if hidden
    ;; Camera masquee : seule la zone non visible (angle mort pres de la camera) reste affichee.
    (if (> nearD 0.0)
      (SC3D:SIDE-BAND
        0.0
        (SC3D:MIN nearD maxD)
        objH
        "SC3D_NON_VISIBLE"
        1
        (SC3D:RGB 120 0 0)
        trans
        T
      )
    )
    (progn
      (if (> nearD 0.0)
        (SC3D:SIDE-BAND
          0.0
          (SC3D:MIN nearD maxD)
          objH
          "SC3D_NON_VISIBLE"
          1
          (SC3D:RGB 120 0 0)
          trans
          T
        )
      )

      (SC3D:SIDE-DRAW-PPM resW maxD nearD tanH tanV tilt camH objH standard trans)

      (if showGrid
        (SC3D:SIDE-GRID maxD camH objH tilt vHalf)
      )

      (SC3D:SIDE-DRAW-AXES maxD camH objH tilt vHalf)

      (SC3D:SIDE-CAMERA-SYMBOL camH tilt)
      (SC3D:SIDE-DRAW-FRUSTUM maxD camH objH tilt vHalf nearD)
      (if showDist
        (SC3D:SIDE-DIST-LABELS maxD camH objH)
      )

      (if *SC3D_CLIP_POLY*
        (SC3D:DRAW-CLIP-CONTOUR *SC3D_CLIP_POLY*)
      )
    )
  )

  (entmake '((0 . "ENDBLK")))
)

(defun SC3D:DELETE-TEXT-HANDLE (vals / h e)
  (setq h (cdr (assoc 'texth vals)))
  (if (and h (/= h ""))
    (progn
      (setq e (handent h))
      ;; entget renvoie nil si l'entite a deja ete supprimee (par exemple a la
      ;; main dans le dessin) : appeler entdel dans ce cas la restaurerait au
      ;; lieu de la laisser supprimee (entdel sur une entite deja effacee
      ;; annule l'effacement au lieu de la supprimer).
      (if (and e (entget e)) (entdel e))
    )
  )
)

(defun SC3D:SUMMARY-TEXT (vals / manu model base)
  (setq manu (cdr (assoc 'manu vals)))
  (setq model (cdr (assoc 'model vals)))

  (setq base
    (strcat
      (cdr (assoc 'fmt vals))
      " / "
      (rtos (cdr (assoc 'focal vals)) 2 1)
      "mm / "
      (SC3D:RES-BASIC (cdr (assoc 'res vals)))
    )
  )

  (if (and manu model (/= manu "Manuel") (/= model "Manuel"))
    (strcat manu " " model "\\P" base)
    base
  )
)

(defun SC3D:SUMMARY-TEXT-SIDE (vals / manu model base)
  ;; Texte de la vue de cote : nom de la camera - infos camera, sur une seule ligne.
  (setq manu (cdr (assoc 'manu vals)))
  (setq model (cdr (assoc 'model vals)))

  (setq base
    (strcat
      (cdr (assoc 'fmt vals))
      " / "
      (rtos (cdr (assoc 'focal vals)) 2 1)
      "mm / "
      (SC3D:RES-BASIC (cdr (assoc 'res vals)))
    )
  )

  (if (and manu model (/= manu "Manuel") (/= model "Manuel"))
    (strcat manu " " model " - " base)
    base
  )
)

(defun SC3D:CAM-INFO-TEXT (vals / manu model calc hAng vAng tiltDeg base)
  ;; Texte d'export (sous la fenetre existante/projetee) : modele - capteur /
  ;; focale / definition / angle H / angle V / inclinaison (axe Y, meme angle
  ;; que celui affiche sur la vue de cote), sur une seule ligne.
  (setq manu (cdr (assoc 'manu vals)))
  (setq model (cdr (assoc 'model vals)))
  (setq calc (SC3D:CALC vals))
  (setq hAng (cdr (assoc 'hAng calc)))
  (setq vAng (cdr (assoc 'vAng calc)))
  (setq tiltDeg (SC3D:RTD (cdr (assoc 'tilt calc))))

  (setq base
    (strcat
      (cdr (assoc 'fmt vals))
      " / "
      (rtos (cdr (assoc 'focal vals)) 2 1)
      "mm / "
      (SC3D:RES-BASIC (cdr (assoc 'res vals)))
      " / H "
      (rtos hAng 2 1)
      "° / V "
      (rtos vAng 2 1)
      "° / Incl "
      (rtos tiltDeg 2 1)
      "°"
    )
  )

  (if (and manu model (/= manu "Manuel") (/= model "Manuel"))
    (strcat manu " " model " - " base)
    base
  )
)

(defun SC3D:CREATE-CAMERA (base vals / calc blockName ins cfg rot camLayer)
  (setq vals (SC3D:SETVAL vals 'view "TOP"))
  (SC3D:SETUP-LAYERS)
  (setq camLayer (SC3D:CAMERA-LAYER-NAME vals))
  (SC3D:LAYER camLayer 2)
  (setq *SC3D_ACTIVE_CAMERA_LAYER* camLayer)

  (setq rot (cdr (assoc 'rot vals)))
  (setq *SC3D_BASE* (list (car base) (cadr base) (if (caddr base) (caddr base) 0.0)))
  (setq *SC3D_ROT* (SC3D:DTR rot))
  (setq *SC3D_CA* (cos *SC3D_ROT*))
  (setq *SC3D_SA* (sin *SC3D_ROT*))

  (setq calc (SC3D:CALC vals))

  (setq blockName (strcat "SC3D_CAMERA_" (rtos (getvar "CDATE") 2 8)))
  (setq blockName (SC3D:REPL blockName "." "_"))

  (SC3D:CREATE-BLOCK-GEOM blockName vals calc)

  (setq ins
    (entmakex
      (list
        '(0 . "INSERT")
        (cons 8 camLayer)
        (cons 2 blockName)
        (cons 10 *SC3D_BASE*)
        '(41 . 1.0)
        '(42 . 1.0)
        '(43 . 1.0)
        (cons 50 *SC3D_ROT*)
      )
    )
  )

  ;; Calque dedie a cette camera (par champ de vision) : gere directement a la
  ;; creation, sans attendre l'export (cf. SC3D:CAM-LAYER-ASSIGN).
  (SC3D:CAM-LAYER-ASSIGN ins vals)

  ;; Le texte recapitulatif n'est plus cree automatiquement : voir SC3D:CMD-GENERER-TEXTE
  ;; (menu Camera, option Texte), pour eviter d'ecraser/dupliquer un texte deja place.
  (setq cfg (SC3D:CFG-STR vals ""))

  (SC3D:SET-XDATA ins cfg)

  (command "_.REGEN")

  (princ (strcat "\nAngle horizontal : " (rtos (cdr (assoc 'hAng calc)) 2 2) " deg"))
  (princ (strcat "\nLargeur CDV : " (rtos (cdr (assoc 'targetWidthMax calc)) 2 2) " m"))

  ins
)

(defun SC3D:CREATE-CAMERA-SIDE (base vals / calc blockName ins cfg rot camLayer)
  (setq vals (SC3D:SETVAL vals 'view "SIDE"))
  (SC3D:SETUP-LAYERS)
  (setq camLayer (SC3D:CAMERA-LAYER-NAME vals))
  (SC3D:LAYER camLayer 2)
  (setq *SC3D_ACTIVE_CAMERA_LAYER* camLayer)

  (setq rot (cdr (assoc 'rot vals)))
  (setq *SC3D_BASE* (list (car base) (cadr base) (if (caddr base) (caddr base) 0.0)))
  (setq *SC3D_ROT* (SC3D:DTR rot))
  (setq *SC3D_CA* (cos *SC3D_ROT*))
  (setq *SC3D_SA* (sin *SC3D_ROT*))

  (setq calc (SC3D:CALC vals))

  (setq blockName (strcat "SC3D_CAMERA_COTE_" (rtos (getvar "CDATE") 2 8)))
  (setq blockName (SC3D:REPL blockName "." "_"))

  (SC3D:CREATE-BLOCK-GEOM-SIDE blockName vals calc)

  (setq ins
    (entmakex
      (list
        '(0 . "INSERT")
        (cons 8 camLayer)
        (cons 2 blockName)
        (cons 10 *SC3D_BASE*)
        '(41 . 1.0)
        '(42 . 1.0)
        '(43 . 1.0)
        (cons 50 *SC3D_ROT*)
      )
    )
  )

  ;; Calque dedie a cette camera (par champ de vision) : gere directement a la
  ;; creation, sans attendre l'export (cf. SC3D:CAM-LAYER-ASSIGN).
  (SC3D:CAM-LAYER-ASSIGN ins vals)

  ;; Le texte recapitulatif n'est plus cree automatiquement : voir SC3D:CMD-GENERER-TEXTE
  ;; (menu Camera, option Texte), pour eviter d'ecraser/dupliquer un texte deja place.
  (setq cfg (SC3D:CFG-STR vals ""))

  (SC3D:SET-XDATA ins cfg)

  (command "_.REGEN")

  (princ (strcat "\nVue de cote creee."))
  (princ (strcat "\nAngle vertical : " (rtos (cdr (assoc 'vAng calc)) 2 2) " deg"))
  (princ (strcat "\nZone non visible : 0 a " (rtos (cdr (assoc 'nearD calc)) 2 2) " m"))

  ins
)

(defun SC3D:CREATE-CAMERA-AUTO (base vals / view)
  (setq view (cdr (assoc 'view vals)))
  (if (= view "SIDE")
    (SC3D:CREATE-CAMERA-SIDE base vals)
    (SC3D:CREATE-CAMERA base vals)
  )
)


(defun SC3D:PPM-AT-DIST (dist vals calc / resW tanH tanV tilt camH objH targetWidth ppm)
  (setq resW (cdr (assoc 'resW calc)))
  (setq tanH (cdr (assoc 'tanH calc)))
  (setq tanV (cdr (assoc 'tanV calc)))
  (setq tilt (cdr (assoc 'tilt calc)))
  (setq camH (cdr (assoc 'camh vals)))
  (setq objH (cdr (assoc 'objh vals)))

  ;; Meme largeur de reference que JVSG pour la densite de pixels.
  ;; Exemple 1/3, 4mm, 1920x1080, D=15m, H=4m, cible=2m : ~105 PPM.
  (setq targetWidth (SC3D:FULL-WIDTH-JVSG-PPM dist tanH tanV tilt camH objH))

  (if (and targetWidth (> targetWidth 0.000001))
    (/ resW targetWidth)
    nil
  )
)

(defun SC3D:PPM-ZONE (ppm standard / lst found z seuil)
  (setq lst (SC3D:PPM-LIST standard))
  (setq found nil)

  (foreach z lst
    (setq seuil (nth 0 z))
    (if (and (null found) (>= ppm seuil))
      (setq found seuil)
    )
  )

  found
)

(defun SC3D:PPM-ZONE-TEXT (zone ppm standard / lastZ)
  (if zone
    (strcat "Zone PPM : " (rtos zone 2 0))
    (progn
      (setq lastZ (last (SC3D:PPM-LIST standard)))
      (if lastZ
        (strcat "Zone PPM : inferieur a " (rtos (nth 0 (car lastZ)) 2 0))
        "Zone PPM : inconnue"
      )
    )
  )
)

(defun SC3D:CMD-CALCULER (/ sel e cfg vals dStr d calc ppm nearD maxD zone standard msg)
  (setq sel (entsel "\nSelectionner la camera : "))

  (if sel
    (progn
      (setq e (car sel))
      (setq cfg (SC3D:GET-XDATA e))

      (if cfg
        (progn
          (setq vals (SC3D:CFG-VALS cfg))

          (if vals
            (progn
              (setq dStr (getstring T "\nDistance a calculer : "))
              (setq d (SC3D:ATOF dStr -1.0))

              (if (<= d 0.0)
                (princ "\nDistance incorrecte.")
                (progn
                  (setq calc (SC3D:CALC vals))
                  (setq nearD (cdr (assoc 'nearD calc)))
                  (setq maxD (cdr (assoc 'dist vals)))
                  (setq standard (cdr (assoc 'std vals)))

                  (if (< d nearD)
                    (progn
                      (princ (strcat "\nDistance : " (rtos d 2 2)))
                      (princ (strcat "\nPPM associe : non visible"))
                      (princ (strcat "\nZone non visible : 0 a " (rtos nearD 2 2)))
                    )
                    (progn
                      (setq ppm (SC3D:PPM-AT-DIST d vals calc))

                      (if ppm
                        (progn
                          (setq zone (SC3D:PPM-ZONE ppm standard))
                          (princ (strcat "\nDistance : " (rtos d 2 2)))
                          (princ (strcat "\nPPM associe : " (rtos ppm 2 0)))
                          (princ (strcat "\n" (SC3D:PPM-ZONE-TEXT zone ppm standard)))

                          (if (> d maxD)
                            (princ (strcat "\nAttention : distance superieure a la distance max de la camera (" (rtos maxD 2 2) ")."))
                          )
                        )
                        (princ "\nImpossible de calculer le PPM pour cette distance.")
                      )
                    )
                  )
                )
              )
            )
            (princ "\nImpossible de lire les informations de cette camera.")
          )
        )
        (princ "\nCe n'est pas une camera generee par S_CAMERA.")
      )
    )
  )

  (princ)
)

(defun SC3D:ASK-ROTATION (/ a)
  ;; getorient (contrairement a getangle) ignore ANGBASE/ANGDIR : la valeur
  ;; recue est toujours dans la convention mathematique standard (0 = axe X
  ;; de l'UCS courant, sens antihoraire), celle utilisee partout ailleurs dans
  ;; ce fichier (SC3D:DTR/RTD, geometrie locale du bloc). Elle reste relative
  ;; a l'UCS courant : on la convertit ensuite en WCS car c'est ce que
  ;; SC3D:CREATE-CAMERA(-SIDE) stocke tel quel dans le DXF 50.
  (setq a (getorient "\nRotation de la camera <0> : "))
  (SC3D:RTD (SC3D:UCS-ANG->WCS (if a a 0.0)))
)

(defun SC3D:CMD-CREER (/ vals base rot)
  (setq vals (SC3D:DIALOG nil))

  (if vals
    (progn
      (setq rot (SC3D:ASK-ROTATION))
      (setq vals (SC3D:SETVAL vals 'rot rot))

      (setq base (getpoint "\nPoint d'insertion de la camera : "))
      (if base
        (setq base (SC3D:UCS-PT->WCS base))
        (setq base '(0.0 0.0 0.0))
      )

      (SC3D:CREATE-CAMERA-AUTO base vals)
    )
  )

  (princ)
)

(defun SC3D:CMD-MODIFIER (/ sel e cfg oldVals newVals ed base oldRot newRot a clip newE)
  (setq sel (entsel "\nSelectionner le bloc camera a modifier : "))

  (if sel
    (progn
      (setq e (car sel))
      (setq ed (entget e))

      (if (and (= (cdr (assoc 0 ed)) "INSERT") (setq cfg (SC3D:GET-XDATA e)))
        (progn
          (setq oldVals (SC3D:CFG-VALS cfg))

          (if oldVals
            (progn
              (setq newVals (SC3D:DIALOG oldVals))

              (if newVals
                (progn
                  (setq base (cdr (assoc 10 ed)))
                  ;; Rotation reelle actuelle du bloc (et non celle memorisee dans le xdata),
                  ;; pour ne pas ecraser une rotation faite entre-temps avec l'outil ROTATE de BricsCAD.
                  (setq oldRot (SC3D:RTD (cdr (assoc 50 ed))))

;; La rotation
;;                  (setq a
;;                    (getangle
;;                      base
;;                      (strcat
;;                        "\nNouvelle rotation de la camera <"
;;                        (rtos oldRot 2 2)
;;                        " deg> : "
;;                      )
;;                    )
;;                  )

                  (if a
                    (setq newRot (SC3D:RTD a))
                    (setq newRot oldRot)
                  )

                  (setq newVals (SC3D:SETVAL newVals 'rot newRot))
                  ;; Conserver l'etat masque/affiche existant : sinon "Modifier" ferait
                  ;; reapparaitre une camera masquee via l'outil Visibilite.
                  (setq newVals (SC3D:SETVAL newVals 'hidden (cdr (assoc 'hidden oldVals))))
                  ;; Recuperer l'ajustement (polygone de decoupe) existant avant de
                  ;; detruire le bloc, pour le reappliquer sur le nouveau bloc cree :
                  ;; sinon "Modifier" fait disparaitre l'ajustement en place.
                  (setq clip (SC3D:GET-CLIP-XDATA e))
                  (SC3D:DELETE-TEXT-HANDLE oldVals)
                  (entdel e)
                  (setq newE (SC3D:CREATE-CAMERA-AUTO base newVals))
                  (if clip
                    (SC3D:APPLY-CLIP newE (car clip) (cdr clip))
                  )
                )
              )
            )
            (princ "\nImpossible de lire les informations de cette camera.")
          )
        )
        (princ "\nCe bloc n'est pas une camera generee par S_CAMERA.")
      )
    )
  )

  (princ)
)

(defun SC3D:MAKE-ADD-CAM-DCL (/ fn f)
  (setq fn (strcat (getvar "TEMPPREFIX") "sc3d_add_camera.dcl"))
  (setq f (open fn "w"))

  (write-line "addcam_dialog : dialog {" f)
  (write-line "  label = \"SNCF - Ajouter un modele de camera\";" f)
  (write-line "  width = 64;" f)
  (write-line "  : column {" f)

  (write-line "    : boxed_column {" f)
  (write-line "      label = \"Identification\";" f)
  (write-line "      : edit_box { key = \"manu\"; label = \"Fabricant\"; edit_width = 26; }" f)
  (write-line "      : edit_box { key = \"model\"; label = \"Modele\"; edit_width = 26; }" f)
  (write-line "    }" f)

  (write-line "    : boxed_column {" f)
  (write-line "      label = \"Caracteristiques\";" f)
  (write-line "      : popup_list { key = \"fmt\"; label = \"Format capteur\"; width = 36; }" f)
  (write-line "      : popup_list { key = \"res\"; label = \"Resolution\"; width = 36; }" f)
  (write-line "      : edit_box { key = \"fmin\"; label = \"Focale min. (mm)\"; edit_width = 10; }" f)
  (write-line "      : edit_box { key = \"fmax\"; label = \"Focale max. (mm)\"; edit_width = 10; }" f)
  (write-line "      : edit_box { key = \"hmax\"; label = \"Angle H a focale min.\"; edit_width = 10; }" f)
  (write-line "      : edit_box { key = \"hmin\"; label = \"Angle H a focale max.\"; edit_width = 10; }" f)
  (write-line "      : edit_box { key = \"vmax\"; label = \"Angle V a focale min.\"; edit_width = 10; }" f)
  (write-line "      : edit_box { key = \"vmin\"; label = \"Angle V a focale max.\"; edit_width = 10; }" f)
  (write-line "    }" f)

  (write-line "    : errtile { key = \"msg\"; }" f)
  (write-line "    ok_cancel;" f)
  (write-line "  }" f)
  (write-line "}" f)

  (close f)
  fn
)

(defun SC3D:ADD-CAM-READ ()
  (list
    (cons 'manu (get_tile "manu"))
    (cons 'model (get_tile "model"))
    (cons 'fmt (nth (atoi (get_tile "fmt")) *SC3D_SENSOR_LIST*))
    (cons 'res (nth (atoi (get_tile "res")) *SC3D_RES_LIST*))
    (cons 'fmin (SC3D:ATOF (get_tile "fmin") 0.0))
    (cons 'fmax (SC3D:ATOF (get_tile "fmax") 0.0))
    (cons 'hmax (SC3D:ATOF (get_tile "hmax") 0.0))
    (cons 'hmin (SC3D:ATOF (get_tile "hmin") 0.0))
    (cons 'vmax (SC3D:ATOF (get_tile "vmax") 0.0))
    (cons 'vmin (SC3D:ATOF (get_tile "vmin") 0.0))
  )
)

(defun SC3D:ADD-CAM-ACCEPT (/ cam)
  (setq cam (SC3D:ADD-CAM-READ))

  (cond
    ((= (cdr (assoc 'manu cam)) "")
      (set_tile "msg" "Entrer un fabricant.")
    )
    ((= (cdr (assoc 'model cam)) "")
      (set_tile "msg" "Entrer un modele.")
    )
    ((<= (cdr (assoc 'fmin cam)) 0.0)
      (set_tile "msg" "Entrer une focale minimum valide.")
    )
    ((<= (cdr (assoc 'fmax cam)) 0.0)
      (set_tile "msg" "Entrer une focale maximum valide.")
    )
    ((> (cdr (assoc 'fmin cam)) (cdr (assoc 'fmax cam)))
      (set_tile "msg" "La focale minimum doit etre inferieure a la focale maximum.")
    )
    ((<= (cdr (assoc 'hmax cam)) 0.0)
      (set_tile "msg" "Entrer l'angle horizontal a la focale minimum.")
    )
    ((<= (cdr (assoc 'hmin cam)) 0.0)
      (set_tile "msg" "Entrer l'angle horizontal a la focale maximum.")
    )
    ((<= (cdr (assoc 'vmax cam)) 0.0)
      (set_tile "msg" "Entrer l'angle vertical a la focale minimum.")
    )
    ((<= (cdr (assoc 'vmin cam)) 0.0)
      (set_tile "msg" "Entrer l'angle vertical a la focale maximum.")
    )
    ((< (cdr (assoc 'hmax cam)) (cdr (assoc 'hmin cam)))
      (set_tile "msg" "L'angle H a la focale min doit etre superieur a l'angle H a la focale max.")
    )
    ((< (cdr (assoc 'vmax cam)) (cdr (assoc 'vmin cam)))
      (set_tile "msg" "L'angle V a la focale min doit etre superieur a l'angle V a la focale max.")
    )
    (T
      (setq SC3D_ADD_CAM_RET cam)
      (done_dialog 1)
    )
  )
)

(defun SC3D:ADD-CAM-DIALOG (/ dcl id result)
  (setq dcl (SC3D:MAKE-ADD-CAM-DCL))
  (setq id (load_dialog dcl))

  (if (not (new_dialog "addcam_dialog" id))
    nil
    (progn
      (start_list "fmt")
      (mapcar 'add_list *SC3D_SENSOR_LIST*)
      (end_list)

      (start_list "res")
      (mapcar 'add_list *SC3D_RES_LIST*)
      (end_list)

      (set_tile "fmt" (itoa (SC3D:INDEXOF "1/2.8" *SC3D_SENSOR_LIST*)))
      (set_tile "res" (itoa (SC3D:INDEXOF "1920x1080 (2MP 16:9)" *SC3D_RES_LIST*)))
      (set_tile "fmin" "2.8")
      (set_tile "fmax" "12")
      ;; Valeurs proches JVSG pour Hanwha Vision XNO-6083R : 2.8-12 mm, H 120-27 deg, V 63-15.4 deg.
      (set_tile "hmax" "120")
      (set_tile "hmin" "27")
      (set_tile "vmax" "63")
      (set_tile "vmin" "15.4")

      (action_tile "accept" "(SC3D:ADD-CAM-ACCEPT)")
      (action_tile "cancel" "(done_dialog 0)")

      (if (= (start_dialog) 1)
        (setq result SC3D_ADD_CAM_RET)
        (setq result nil)
      )

      (unload_dialog id)
      result
    )
  )
)

(defun SC3D:CMD-AJOUTER (/ cam cams out replaced)
  (setq cam (SC3D:ADD-CAM-DIALOG))

  (if cam
    (progn
      (setq cams (SC3D:LOAD-CAMERAS))
      (setq out '())
      (setq replaced nil)

      (foreach c cams
        (if (and
              (= (strcase (cdr (assoc 'manu c))) (strcase (cdr (assoc 'manu cam))))
              (= (strcase (cdr (assoc 'model c))) (strcase (cdr (assoc 'model cam))))
            )
          (progn
            (setq out (append out (list cam)))
            (setq replaced T)
          )
          (setq out (append out (list c)))
        )
      )

      (if (not replaced)
        (setq out (append out (list cam)))
      )

      (SC3D:SAVE-CAMERAS out)

      (princ
        (strcat
          "\nCamera enregistree dans : "
          (SC3D:CFG-PATH)
        )
      )
    )
  )

  (princ)
)

(defun SC3D:MAKE-DEL-CAM-DCL (/ fn f)
  (setq fn (strcat (getvar "TEMPPREFIX") "sc3d_del_camera.dcl"))
  (setq f (open fn "w"))

  (write-line "delcam_dialog : dialog {" f)
  (write-line "  label = \"SNCF - Supprimer un modele de camera\";" f)
  (write-line "  width = 44;" f)
  (write-line "  : column {" f)

  (write-line "    : boxed_column {" f)
  (write-line "      label = \"Camera a supprimer\";" f)
  (write-line "      : popup_list { key = \"manu\"; label = \"Fabricant\"; width = 34; }" f)
  (write-line "      : popup_list { key = \"model\"; label = \"Modele\"; width = 34; }" f)
  (write-line "    }" f)

  (write-line "    : errtile { key = \"msg\"; }" f)
  (write-line "    ok_cancel;" f)
  (write-line "  }" f)
  (write-line "}" f)

  (close f)
  fn
)

(defun SC3D:DEL-DLG-UPDATE-MODELS (/ manu)
  (setq manu (nth (atoi (get_tile "manu")) *SC3D_DEL_MFR_LIST*))
  (setq *SC3D_DEL_MODEL_LIST* (SC3D:CAM-MODEL-LIST manu))

  (if (= manu "Manuel")
    (setq *SC3D_DEL_MODEL_LIST* '("Aucune camera"))
  )

  (SC3D:SET-POPUP-LIST "model" *SC3D_DEL_MODEL_LIST* (car *SC3D_DEL_MODEL_LIST*))
)

(defun SC3D:DEL-DLG-ACCEPT (/ manu model)
  (setq manu (nth (atoi (get_tile "manu")) *SC3D_DEL_MFR_LIST*))
  (setq model (nth (atoi (get_tile "model")) *SC3D_DEL_MODEL_LIST*))

  (if (or (= manu "Manuel") (= model "Aucune camera"))
    (set_tile "msg" "Selectionner une camera valide.")
    (progn
      (setq SC3D_DEL_CAM_RET (list (cons 'manu manu) (cons 'model model)))
      (done_dialog 1)
    )
  )
)

(defun SC3D:DEL-CAM-DIALOG (/ dcl id result)
  (setq dcl (SC3D:MAKE-DEL-CAM-DCL))
  (setq id (load_dialog dcl))

  (if (not (new_dialog "delcam_dialog" id))
    nil
    (progn
      (setq *SC3D_DEL_MFR_LIST* (SC3D:CAM-MFR-LIST))

      (start_list "manu")
      (mapcar 'add_list *SC3D_DEL_MFR_LIST*)
      (end_list)

      (set_tile "manu" "0")
      (setq *SC3D_DEL_MODEL_LIST* '("Aucune camera"))
      (SC3D:SET-POPUP-LIST "model" *SC3D_DEL_MODEL_LIST* "Aucune camera")

      (action_tile "manu" "(SC3D:DEL-DLG-UPDATE-MODELS)")
      (action_tile "accept" "(SC3D:DEL-DLG-ACCEPT)")
      (action_tile "cancel" "(done_dialog 0)")

      (if (= (start_dialog) 1)
        (setq result SC3D_DEL_CAM_RET)
        (setq result nil)
      )

      (unload_dialog id)
      result
    )
  )
)

(defun SC3D:CMD-SUPPRIMER (/ target cams out removed)
  (setq target (SC3D:DEL-CAM-DIALOG))

  (if target
    (progn
      (setq cams (SC3D:LOAD-CAMERAS))
      (setq out '())
      (setq removed nil)

      (foreach cam cams
        (if (and
              (= (cdr (assoc 'manu cam)) (cdr (assoc 'manu target)))
              (= (cdr (assoc 'model cam)) (cdr (assoc 'model target)))
            )
          (setq removed T)
          (setq out (append out (list cam)))
        )
      )

      (SC3D:SAVE-CAMERAS out)

      (if removed
        (princ "\nCamera supprimee.")
        (princ "\nCamera introuvable.")
      )
    )
  )

  (princ)
)

(defun SC3D:CAMERA-INSERT-P (e / ed)
  (if e
    (progn
      (setq ed (entget e))
      (and
        (= (cdr (assoc 0 ed)) "INSERT")
        (SC3D:GET-XDATA e)
      )
    )
    nil
  )
)

(defun SC3D:SELECT-CAMERA-BLOCK (msg / sel e)
  (setq sel (entsel msg))
  (if sel
    (progn
      (setq e (car sel))
      (if (SC3D:CAMERA-INSERT-P e)
        e
        (progn
          (princ "\nCe bloc n'est pas une camera generee par S_CAMERA.")
          nil
        )
      )
    )
    nil
  )
)

(defun SC3D:TEMP-DELETE (ents)
  (foreach e ents
    (if (and e (entget e))
      (entdel e)
    )
  )
)

(defun SC3D:TEMP-LINE (p1 p2 / e)
  ;; Ligne temporaire visible pendant le trace du polygone.
  ;; Elle est supprimee automatiquement apres validation ou annulation.
  (setq e
    (entmakex
      (list
        '(0 . "LINE")
        (cons 8 "SC3D_AJUSTEMENT")
        (cons 62 30)
        (cons 10 p1)
        (cons 11 p2)
      )
    )
  )
  (if e
    (progn
      (entupd e)
      (redraw e 3)
    )
  )
  e
)

(defun SC3D:UNDO-LAST-PT (lst)
  ;; Retire le dernier element d'une liste (pas de butlast en AutoLISP).
  (reverse (cdr (reverse lst)))
)

(defun SC3D:GET-POLY-POINTS (/ pts pt tempEnts closeEnt olderr result finished)
  (SC3D:LAYER "SC3D_AJUSTEMENT" 30)

  (setq pts '())
  (setq tempEnts '())
  (setq closeEnt nil)
  (setq result nil)
  (setq finished nil)
  (setq olderr *error*)

  (defun *error* (msg)
    (if closeEnt
      (SC3D:TEMP-DELETE (list closeEnt))
    )
    (SC3D:TEMP-DELETE tempEnts)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (princ (strcat "\nErreur : " msg))
    )
    (princ)
  )

  (while (not finished)
    (if (= (length pts) 0)
      ;; Premier point : rien a annuler pour l'instant.
      (progn
        (setq pt (getpoint "\nPremier point du polygone d'ajustement : "))
        (if pt
          (setq pts (list pt))
          (setq finished T)
        )
      )
      (progn
        ;; Points suivants : "Annuler" permet de revenir sur le dernier point
        ;; saisi sans devoir recommencer tout le polygone.
        (initget "Annuler")
        (setq pt
          (getpoint
            (last pts)
            (if (< (length pts) 3)
              "\nPoint suivant ou [Annuler] : "
              "\nPoint suivant ou Entree pour terminer [Annuler] : "
            )
          )
        )
        (cond
          ((null pt)
            (setq finished T)
          )
          ((= pt "Annuler")
            (setq pts (SC3D:UNDO-LAST-PT pts))
            (if tempEnts
              (progn
                (SC3D:TEMP-DELETE (list (last tempEnts)))
                (setq tempEnts (SC3D:UNDO-LAST-PT tempEnts))
              )
            )
            (if closeEnt
              (progn
                (SC3D:TEMP-DELETE (list closeEnt))
                (setq closeEnt nil)
              )
            )
            (if (>= (length pts) 3)
              (setq closeEnt
                (SC3D:TEMP-LINE (SC3D:UCS-PT->WCS (last pts)) (SC3D:UCS-PT->WCS (car pts)))
              )
            )
            (princ "\nDernier point annule.")
          )
          (T
            ;; Affiche le segment nouvellement valide. entmake (dans SC3D:TEMP-LINE)
            ;; attend des points WCS, alors que pts est encore exprime dans l'UCS
            ;; courant (necessaire pour chainer les getpoint).
            (setq tempEnts
              (append tempEnts
                (list (SC3D:TEMP-LINE (SC3D:UCS-PT->WCS (last pts)) (SC3D:UCS-PT->WCS pt)))
              )
            )
            (setq pts (append pts (list pt)))

            ;; Affiche aussi la fermeture provisoire du polygone.
            (if closeEnt
              (progn
                (SC3D:TEMP-DELETE (list closeEnt))
                (setq closeEnt nil)
              )
            )
            (if (>= (length pts) 3)
              (setq closeEnt (SC3D:TEMP-LINE (SC3D:UCS-PT->WCS pt) (SC3D:UCS-PT->WCS (car pts))))
            )
          )
        )
      )
    )
  )

  (if (>= (length pts) 3)
    ;; Le resultat est converti en WCS : il sera combine avec le point d'insertion
    ;; et la rotation du bloc (donnees d'entite, donc WCS) par SC3D:WORLD->LOCAL-POLY.
    (setq result (mapcar 'SC3D:UCS-PT->WCS pts))
    (progn
      (princ "\nIl faut au moins 3 points pour un polygone.")
      (setq result nil)
    )
  )

  ;; Les lignes jaunes ne servent que d'aide au trace.
  ;; L'ajustement final est ensuite applique par le decoupage geometrique custom.
  (if closeEnt
    (SC3D:TEMP-DELETE (list closeEnt))
  )
  (SC3D:TEMP-DELETE tempEnts)
  (setq *error* olderr)

  result
)

;; ------------------------------------------------------------------------------------
;; Stockage de l'ajustement (polygone en coordonnees locales du bloc) dans les
;; xdata de l'INSERT, sous une appid dediee. Independant du xdata de configuration
;; camera (SC3D_APP) pour ne jamais interferer avec SC3D:CFG-VALS.
;; ------------------------------------------------------------------------------------

(setq *SC3D_CLIP_APP* "SC3D_CAMERA_CLIP")

(defun SC3D:REGAPP-CLIP ()
  (if (not (tblsearch "APPID" *SC3D_CLIP_APP*))
    (regapp *SC3D_CLIP_APP*)
  )
)

(defun SC3D:CLIP-PTS->STRING (pts / s pt)
  (setq s "")
  (foreach pt pts
    (setq s (strcat s (rtos (car pt) 2 6) " " (rtos (cadr pt) 2 6) ";"))
  )
  s
)

(defun SC3D:CLIP-STRING->PTS (s / out tok xy)
  (setq out '())
  (foreach tok (SC3D:SPLIT s ";")
    (if (/= tok "")
      (progn
        (setq xy (SC3D:SPLIT tok " "))
        (if (>= (length xy) 2)
          (setq out
            (append out
              (list (list (SC3D:ATOF (nth 0 xy) 0.0) (SC3D:ATOF (nth 1 xy) 0.0)))
            )
          )
        )
      )
    )
  )
  out
)

(defun SC3D:STRING-CHUNKS (s size / out i n)
  ;; Decoupe s en morceaux de taille size (independamment des mots), pour rester
  ;; sous la limite de 255 caracteres d'une entree xdata 1000. Les morceaux sont
  ;; reconcatenes dans l'ordre a la lecture, donc la coupure peut tomber n'importe ou.
  (setq out '())
  (setq n (strlen s))
  (setq i 1)
  (while (<= i n)
    (setq out (append out (list (substr s i size))))
    (setq i (+ i size))
  )
  out
)

(defun SC3D:SET-CLIP-XDATA (e active pts / s chunks lst c)
  (SC3D:REGAPP-CLIP)
  (setq s (SC3D:CLIP-PTS->STRING pts))
  (setq chunks (SC3D:STRING-CHUNKS s 200))
  (setq lst (list *SC3D_CLIP_APP* (cons 1070 (if active 1 0))))
  (foreach c chunks
    (setq lst (append lst (list (cons 1000 c))))
  )
  (entmod (append (entget e) (list (list -3 lst))))
  (entupd e)
)

(defun SC3D:GET-CLIP-XDATA (e / xd entry active chunks x pts)
  (setq xd (cdr (assoc -3 (entget e (list *SC3D_CLIP_APP*)))))
  (if xd
    (progn
      (setq entry (assoc *SC3D_CLIP_APP* xd))
      (if entry
        (progn
          (setq active nil)
          (setq chunks "")
          (foreach x (cdr entry)
            (cond
              ((= (car x) 1070) (setq active (= (cdr x) 1)))
              ((= (car x) 1000) (setq chunks (strcat chunks (cdr x))))
            )
          )
          (setq pts (SC3D:CLIP-STRING->PTS chunks))
          (if (>= (length pts) 3)
            (cons active pts)
            nil
          )
        )
        nil
      )
    )
    nil
  )
)

(defun SC3D:CLEAR-CLIP-XDATA (e)
  (SC3D:REGAPP-CLIP)
  (entmod (append (entget e) (list (list -3 (list *SC3D_CLIP_APP*)))))
  (entupd e)
)

(defun SC3D:WORLD->LOCAL-PT (pt base rot / dx dy ca sa)
  (setq dx (- (car pt) (car base)))
  (setq dy (- (cadr pt) (cadr base)))
  (setq ca (cos rot))
  (setq sa (sin rot))
  (list (+ (* dx ca) (* dy sa)) (+ (* (- dx) sa) (* dy ca)))
)

(defun SC3D:WORLD->LOCAL-POLY (pts base rot / out p)
  (setq out '())
  (foreach p pts
    (setq out (append out (list (SC3D:WORLD->LOCAL-PT p base rot))))
  )
  out
)

(defun SC3D:APPLY-CLIP (e active localPts / ed blockName cfg vals calc view)
  ;; Regenere la geometrie du bloc camera (meme nom de bloc = redefinition en
  ;; place) avec ou sans decoupe par localPts, sans jamais appeler XCLIP.
  (SC3D:LAYER "SC3D_AJUSTEMENT" 30)
  (setq ed (entget e))
  (setq blockName (cdr (assoc 2 ed)))
  (setq cfg (SC3D:GET-XDATA e))
  (setq vals (if cfg (SC3D:CFG-VALS cfg) nil))

  (if (not vals)
    (progn
      (princ "\nImpossible de lire les informations de cette camera.")
      nil
    )
    (progn
      (setq calc (SC3D:CALC vals))
      (setq view (cdr (assoc 'view vals)))

      (setq *SC3D_CLIP_POLY* (if active localPts nil))
      (setq *SC3D_CLIP_TRIS*
        (if *SC3D_CLIP_POLY* (SC3D:EAR-CLIP-TRIANGULATE *SC3D_CLIP_POLY*) nil)
      )

      (if (= view "SIDE")
        (SC3D:CREATE-BLOCK-GEOM-SIDE blockName vals calc)
        (SC3D:CREATE-BLOCK-GEOM blockName vals calc)
      )

      (setq *SC3D_CLIP_POLY* nil)
      (setq *SC3D_CLIP_TRIS* nil)

      (if localPts
        (SC3D:SET-CLIP-XDATA e active localPts)
        (SC3D:CLEAR-CLIP-XDATA e)
      )

      (command "_.REGEN")
      T
    )
  )
)

;; ------------------------------------------------------------------------------------
;; VISIBILITE (Cacher / Afficher un ou plusieurs blocs camera)
;;
;; ------------------------------------------------------------------------------------

(defun SC3D:REGEN-CAMERA-GEOM (e / ed blockName cfg vals calc view clip active pts)
  ;; Regenere la geometrie du bloc camera en place a partir des xdata actuelles
  ;; (configuration + ajustement existant), sans les modifier.
  (setq ed (entget e))
  (setq blockName (cdr (assoc 2 ed)))
  (setq cfg (SC3D:GET-XDATA e))
  (setq vals (if cfg (SC3D:CFG-VALS cfg) nil))

  (if (not vals)
    nil
    (progn
      (setq calc (SC3D:CALC vals))
      (setq view (cdr (assoc 'view vals)))

      (setq clip (SC3D:GET-CLIP-XDATA e))
      (setq active (and clip (car clip)))
      (setq pts (if clip (cdr clip) nil))

      (setq *SC3D_CLIP_POLY* (if active pts nil))
      (setq *SC3D_CLIP_TRIS*
        (if *SC3D_CLIP_POLY* (SC3D:EAR-CLIP-TRIANGULATE *SC3D_CLIP_POLY*) nil)
      )

      (if (= view "SIDE")
        (SC3D:CREATE-BLOCK-GEOM-SIDE blockName vals calc)
        (SC3D:CREATE-BLOCK-GEOM blockName vals calc)
      )

      (setq *SC3D_CLIP_POLY* nil)
      (setq *SC3D_CLIP_TRIS* nil)

      T
    )
  )
)

(defun SC3D:SET-CAMERA-HIDDEN (e hidden / cfg vals texth newCfg)
  (setq cfg (SC3D:GET-XDATA e))
  (setq vals (if cfg (SC3D:CFG-VALS cfg) nil))

  (if (not vals)
    nil
    (progn
      (setq vals (SC3D:SETVAL vals 'hidden hidden))
      (setq texth (cdr (assoc 'texth vals)))
      (setq newCfg (SC3D:CFG-STR vals (if texth texth "")))
      (SC3D:SET-XDATA e newCfg)
      (SC3D:REGEN-CAMERA-GEOM e)
    )
  )
)

(defun SC3D:SELECT-CAMERA-BLOCKS (msg / ss n i e out)
  (setq ss (ssget msg (list '(0 . "INSERT") (list -3 (list *SC3D_APP*)))))
  (setq out '())
  (if ss
    (progn
      (setq n (sslength ss))
      (setq i 0)
      (while (< i n)
        (setq e (ssname ss i))
        (if (SC3D:CAMERA-INSERT-P e)
          (setq out (append out (list e)))
        )
        (setq i (+ i 1))
      )
    )
  )
  out
)

(defun SC3D:CMD-VISIBILITE (/ ents choix hidden n)
  (setq ents (SC3D:SELECT-CAMERA-BLOCKS "\nSelectionner un ou plusieurs blocs camera : "))

  (if (not ents)
    (princ "\nAucun bloc camera selectionne.")
    (progn
      (initget "Cacher Afficher")
      (setq choix (getkword "\nVisibilite [Cacher/Afficher] <Cacher> : "))
      (if (null choix) (setq choix "Cacher"))
      (setq hidden (= choix "Cacher"))

      (setq n 0)
      (foreach e ents
        (if (SC3D:SET-CAMERA-HIDDEN e hidden)
          (setq n (+ n 1))
        )
      )

      (command "_.REGEN")

      (if hidden
        (princ (strcat "\n" (itoa n) " camera(s) masquee(s) : seule la zone non visible reste affichee."))
        (princ (strcat "\n" (itoa n) " camera(s) affichee(s)."))
      )
    )
  )

  (princ)
)

(defun SC3D:CMD-AJUSTER (/ e choix ed base rot p1 p2 wpts lpts stored)
  (setq e (SC3D:SELECT-CAMERA-BLOCK "\nSelectionner le bloc camera a ajuster : "))

  (if e
    (progn
      (setq ed (entget e))
      (setq base (cdr (assoc 10 ed)))
      (setq rot (cdr (assoc 50 ed)))
      (if (not rot) (setq rot 0.0))

      (initget "Rectangle Polygone Afficher Masquer Supprimer")
      (setq choix
        (getkword
          "\nAjuster [Rectangle/Polygone/Afficher/Masquer/Supprimer] <Rectangle> : "
        )
      )

      (if (null choix)
        (setq choix "Rectangle")
      )

      (cond
        ((= choix "Rectangle")
          (setq p1 (getpoint "\nPremier coin du rectangle d'ajustement : "))
          (if p1
            (progn
              (setq p2 (getcorner p1 "\nCoin oppose : "))
              (if p2
                (progn
                  ;; Rectangle aligne sur l'UCS courant (p1/p2) : on construit ses coins
                  ;; dans l'UCS puis on les convertit en WCS pour les combiner avec
                  ;; base/rot (donnees d'entite, donc WCS).
                  (setq wpts
                    (mapcar 'SC3D:UCS-PT->WCS
                      (list
                        p1
                        (list (car p2) (cadr p1))
                        p2
                        (list (car p1) (cadr p2))
                      )
                    )
                  )
                  (setq lpts (SC3D:WORLD->LOCAL-POLY wpts base rot))
                  (if (SC3D:APPLY-CLIP e T lpts)
                    (princ "\nAjustement rectangle applique.")
                  )
                )
              )
            )
          )
        )
        ((= choix "Polygone")
          (setq wpts (SC3D:GET-POLY-POINTS))
          (if wpts
            (progn
              (setq lpts (SC3D:WORLD->LOCAL-POLY wpts base rot))
              (if (SC3D:APPLY-CLIP e T lpts)
                (princ "\nAjustement polygone applique.")
              )
            )
          )
        )
        ((= choix "Afficher")
          (setq stored (SC3D:GET-CLIP-XDATA e))
          (if stored
            (if (SC3D:APPLY-CLIP e T (cdr stored))
              (princ "\nAjustement affiche : le champ de vision est decoupe.")
            )
            (princ "\nAucun ajustement defini pour cette camera.")
          )
        )
        ((= choix "Masquer")
          (setq stored (SC3D:GET-CLIP-XDATA e))
          (if stored
            (if (SC3D:APPLY-CLIP e nil (cdr stored))
              (princ "\nAjustement masque : le champ de vision complet est visible.")
            )
            (princ "\nAucun ajustement defini pour cette camera.")
          )
        )
        ((= choix "Supprimer")
          (if (SC3D:APPLY-CLIP e nil nil)
            (princ "\nAjustement supprime.")
          )
        )
      )
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------
;; REPERE "NOM DU CHAMP DE VISION" (rectangle + fleche directe vers la camera)
;; ------------------------------------------------------------------------------------

(defun SC3D:RECT-EXIT-POINT (cx cy hw hh dx dy / tx ty tt)
  ;; Point ou le rayon issu du centre (cx cy) d'un rectangle axe (demi-largeur hw,
  ;; demi-hauteur hh), en direction (dx dy), sort du rectangle. Utilise pour faire
  ;; partir la fleche du bord du cadre plutot que de son centre (par-dessus le texte).
  (if (and (equal dx 0.0 1e-6) (equal dy 0.0 1e-6)) (setq dx 1.0))
  (setq tx (if (equal dx 0.0 1e-6) 1e9 (/ hw (abs dx))))
  (setq ty (if (equal dy 0.0 1e-6) 1e9 (/ hh (abs dy))))
  (setq tt (SC3D:MIN tx ty))
  (list (+ cx (* tt dx)) (+ cy (* tt dy)) 0.0)
)

(defun SC3D:MODEL-RECT (p1 p2 lay col / x1 y1 x2 y2)
  ;; Rectangle en espace objet, trace avec 4 lignes brutes (non decoupees).
  (setq x1 (car p1)) (setq y1 (cadr p1))
  (setq x2 (car p2)) (setq y2 (cadr p2))
  (SC3D:LINE-RAW (list x1 y1 0.0) (list x2 y1 0.0) lay col)
  (SC3D:LINE-RAW (list x2 y1 0.0) (list x2 y2 0.0) lay col)
  (SC3D:LINE-RAW (list x2 y2 0.0) (list x1 y2 0.0) lay col)
  (SC3D:LINE-RAW (list x1 y2 0.0) (list x1 y1 0.0) lay col)
)

(defun SC3D:LEADER-ARROW (p1 p2 lay col)
  ;; Ligne directe de p1 a p2 (le champ de vision), sans pointe de fleche.
  (SC3D:LINE-RAW (list (car p1) (cadr p1) 0.0) (list (car p2) (cadr p2) 0.0) lay col)
)

(defun SC3D:CREATE-LABEL-CV (camPt pt cvname / textH charW textW margin cx cy hw hh dx dy leaderStart blockName ins)
  ;; Cree un bloc regroupant rectangle + texte (nom du champ de vision) + fleche
  ;; directe vers camPt, et l'insere en un seul point (0,0,0) : toute la geometrie
  ;; est deja en coordonnees WCS absolues, ce qui permet de ne suivre qu'une seule
  ;; entite (l'INSERT) pour la suppression/regeneration ulterieure.
  ;; NB : ce bloc ne recoit PAS le xdata de l'application (SC3D_CAMERA), pour ne
  ;; jamais etre confondu avec un bloc camera par SC3D:CAMERA-INSERT-P et les
  ;; selections qui s'y appuient (Export, Visibilite, etc.).
  (setq textH 0.30)
  (setq charW (* 0.6 textH))
  (setq textW (SC3D:MAX (* charW (strlen cvname)) (* 2.0 textH)))
  (setq margin 0.15)

  (setq cx (car pt))
  (setq cy (cadr pt))
  (setq hw (+ (/ textW 2.0) margin))
  (setq hh (+ (/ textH 2.0) margin))

  (setq dx (- (car camPt) cx))
  (setq dy (- (cadr camPt) cy))
  (setq leaderStart (SC3D:RECT-EXIT-POINT cx cy hw hh dx dy))

  (setq blockName (strcat "SC3D_LABEL_" (SC3D:REPL (rtos (getvar "CDATE") 2 8) "." "_")))

  (entmake (list '(0 . "BLOCK") (cons 2 blockName) '(70 . 0) '(10 0.0 0.0 0.0)))
  (SC3D:MODEL-RECT (list (- cx hw) (- cy hh) 0.0) (list (+ cx hw) (+ cy hh) 0.0) "SC3D_TEXTES" 7)
  (SC3D:TEXT-WORLD pt textH cvname "SC3D_TEXTES" 7 0.0)
  (SC3D:LEADER-ARROW leaderStart camPt "SC3D_TEXTES" 7)
  (entmake '((0 . "ENDBLK")))

  (setq ins
    (entmakex
      (list
        '(0 . "INSERT")
        (cons 8 "SC3D_TEXTES")
        (cons 2 blockName)
        (cons 10 (list 0.0 0.0 0.0))
        '(41 . 1.0)
        '(42 . 1.0)
        '(43 . 1.0)
        (cons 50 0.0)
      )
    )
  )
  ins
)

(defun SC3D:GENERER-TEXTE-TYPE (e vals base rot view / txtPt txt txtH newCfg)
  ;; Supprime l'ancien texte lie (s'il existe) avant d'en creer un nouveau,
  ;; pour ne jamais en laisser deux en meme temps.
  (SC3D:DELETE-TEXT-HANDLE vals)

  (setq *SC3D_BASE* (list (car base) (cadr base) (if (caddr base) (caddr base) 0.0)))
  (setq *SC3D_CA* (cos rot))
  (setq *SC3D_SA* (sin rot))

  (setq txtPt
    (if (= view "SIDE")
      (SC3D:PW 0.45 (+ (cdr (assoc 'camh vals)) 0.85) 0.0)
      (SC3D:PW 0.45 -0.75 0.45)
    )
  )

  (setq txt
    (SC3D:TEXT-WORLD
      txtPt
      0.30
      (if (= view "SIDE") (SC3D:SUMMARY-TEXT-SIDE vals) (SC3D:SUMMARY-TEXT vals))
      "SC3D_TEXTES"
      7
      0.0
    )
  )

  (setq txtH (cdr (assoc 5 (entget txt))))
  (setq newCfg (SC3D:CFG-STR vals txtH))

  (SC3D:SET-XDATA e newCfg)
  (SC3D:SET-XDATA txt newCfg)

  (command "_.REGEN")
  (princ "\nTexte genere.")
)

(defun SC3D:GENERER-TEXTE-NOM (e vals base / cvname camPt pt ins newCfg)
  (setq cvname (cdr (assoc 'cvname vals)))
  (if (or (null cvname) (= cvname ""))
    (princ "\nAucun nom de champ de vision defini pour cette camera (voir Modifier).")
    (progn
      (setq camPt (list (car base) (cadr base) (if (caddr base) (caddr base) 0.0)))
      (setq pt (getpoint "\nPoint d'insertion du repere (nom du champ de vision) : "))

      (if (null pt)
        (princ "\nAnnule.")
        (progn
          ;; Supprime l'ancien texte lie (s'il existe) avant d'en creer un nouveau,
          ;; pour ne jamais en laisser deux en meme temps.
          (SC3D:DELETE-TEXT-HANDLE vals)

          (setq ins (SC3D:CREATE-LABEL-CV camPt pt cvname))

          (setq newCfg (SC3D:CFG-STR vals (cdr (assoc 5 (entget ins)))))
          (SC3D:SET-XDATA e newCfg)

          (command "_.REGEN")
          (princ "\nTexte genere.")
        )
      )
    )
  )
)

(defun SC3D:CMD-GENERER-TEXTE (/ e ed cfg vals base rot view mode)
  ;; Cree (ou recree) le texte recapitulatif d'une camera existante, a la demande
  ;; (le texte n'est plus genere automatiquement par Creer/Modifier).
  ;; Deux contenus possibles : le type de camera (texte recapitulatif fixe, comme
  ;; avant) ou le nom du champ de vision (repere rectangle + fleche, positionne
  ;; librement puis relie a la camera par une fleche directe).
  (setq e (SC3D:SELECT-CAMERA-BLOCK "\nSelectionner le bloc camera pour generer le texte : "))

  (if e
    (progn
      (setq ed (entget e))
      (setq cfg (SC3D:GET-XDATA e))
      (setq vals (if cfg (SC3D:CFG-VALS cfg) nil))

      (if vals
        (progn
          (setq base (cdr (assoc 10 ed)))
          (setq rot (cdr (assoc 50 ed)))
          (if (not rot) (setq rot 0.0))
          (setq view (cdr (assoc 'view vals)))

          (initget "Type Nom")
          (setq mode
            (getkword "\nContenu du texte [Type de camera/Nom du champ de vision] <Type> : ")
          )
          (if (null mode) (setq mode "Type"))

          (if (= mode "Nom")
            (SC3D:GENERER-TEXTE-NOM e vals base)
            (SC3D:GENERER-TEXTE-TYPE e vals base rot view)
          )
        )
        (princ "\nImpossible de lire les informations de cette camera.")
      )
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------
;; EXPORT EN PRESENTATIONS
;;
;; Pour chaque camera selectionnee, une presentation (layout) est creee, avec un
;; dezoom qui cadre l'integralite de son champ de vision. Dans chaque fenetre,
;; toutes les autres cameras du dessin sont "cachees" par gel de calque propre a
;; la fenetre (VP freeze) : le modele n'est jamais modifie, chaque presentation
;; montre donc uniquement sa camera.
;;
;; Format papier : 3 x A4 portrait cote a cote (630 x 297 mm).
;;   - 1er A4 : fenetre sur la zone de legende choisie dans le dessin (optionnel)
;;   - 2e  A4 : situation existante (ou camera seule)
;;   - 3e  A4 : situation projetee (uniquement pour les paires existante/projetee),
;;              cadree sur son propre champ de vision, a l'endroit ou il se trouve
;;              dans le dessin, avec la camera existante cachee.
;;
;; Nom de la presentation : nom du champ de vision, sinon CV_1, CV_2, ...
;; Si deux champs de vision selectionnes portent le meme nom et que l'un est
;; "Existante" et l'autre "Projetee", une seule presentation combinee est creee.
;;
;; La fenetre creee par defaut avec toute nouvelle presentation est supprimee.
;;
;; NOTE : pour permettre le gel individuel, chaque bloc camera est deplace sur son
;; propre calque SC3D_CV_<handle> (couleur 2) au moment de l'export. Le gel est
;; applique avec VPLAYER (gel SC3D_CV_* puis degel du seul calque a presenter).
;; ------------------------------------------------------------------------------------

(setq *SC3D_A4_W* 210.0)
(setq *SC3D_A4_H* 297.0)
(setq *SC3D_VP_MARGIN* 10.0)
(setq *SC3D_PAGE_MARGIN* 13.0)
(setq *SC3D_EXPORT_ZOOM* 10.0)
(setq *SC3D_CV_COUNTER* 0)

(defun SC3D:ACAD-DOC ()
  (vla-get-ActiveDocument (vlax-get-acad-object))
)

(defun SC3D:SSGET-CAMERAS (mode / ss out n i e)
  ;; mode = nil : selection interactive ; mode = "_X" : toutes les cameras du dessin.
  (setq ss
    (if mode
      (ssget mode (list '(0 . "INSERT") (list -3 (list *SC3D_APP*))))
      (ssget (list '(0 . "INSERT") (list -3 (list *SC3D_APP*))))
    )
  )
  (setq out '())
  (if ss
    (progn
      (setq n (sslength ss))
      (setq i 0)
      (while (< i n)
        (setq e (ssname ss i))
        (if (SC3D:CAMERA-INSERT-P e)
          (setq out (append out (list e)))
        )
        (setq i (+ i 1))
      )
    )
  )
  out
)

(defun SC3D:ENT-BBOX (e / obj mn mx)
  (setq obj (vlax-ename->vla-object e))
  (vla-GetBoundingBox obj 'mn 'mx)
  (list (vlax-safearray->list mn) (vlax-safearray->list mx))
)

(defun SC3D:CAM-REC (e / cfg vals bb)
  ;; Fiche d'export d'une camera : entite, calque dedie, nom, situation, emprise.
  (setq cfg (SC3D:GET-XDATA e))
  (setq vals (if cfg (SC3D:CFG-VALS cfg) nil))
  (if vals
    (progn
      (setq bb (SC3D:ENT-BBOX e))
      (list
        (cons 'ent e)
        (cons 'lay (SC3D:CAM-LAYER-ASSIGN e vals))
        (cons 'name (if (cdr (assoc 'cvname vals)) (cdr (assoc 'cvname vals)) ""))
        (cons 'sit (if (cdr (assoc 'situation vals)) (cdr (assoc 'situation vals)) ""))
        (cons 'bmin (car bb))
        (cons 'bmax (cadr bb))
        (cons 'vals vals)
      )
    )
    nil
  )
)

(defun SC3D:LAYOUT-EXISTS-P (name)
  (member (strcase name) (mapcar 'strcase (layoutlist)))
)

(defun SC3D:DELETE-EXPORT-LAYOUTS (/ doc names nm layObj ent r count)
  ;; Supprime toutes les presentations generees par un export precedent
  ;; (reperees par le xdata pose sur chacune a sa creation, cf.
  ;; SC3D:EXPORT-MAKE-LAYOUT) : les presentations propres a l'utilisateur, non
  ;; marquees, restent intactes.
  ;; NB : LAYOUT n'est pas une table classique (LAYER, STYLE, BLOCK...), donc
  ;; pas de tblobjname possible : on passe par la collection Layouts (VLA) pour
  ;; recuperer l'ename de chaque presentation.
  (setq doc (SC3D:ACAD-DOC))
  (if (/= (getvar "CTAB") "Model") (setvar "CTAB" "Model"))
  (setq count 0)
  (setq names (layoutlist))
  (foreach nm names
    (if (/= (strcase nm) "MODEL")
      (progn
        (setq layObj (vl-catch-all-apply 'vla-Item (list (vla-get-Layouts doc) nm)))
        (if (not (vl-catch-all-error-p layObj))
          (progn
            (setq ent (vlax-vla-object->ename layObj))
            (if (and ent (SC3D:GET-XDATA ent))
              (progn
                (setq r (vl-catch-all-apply 'vla-Delete (list layObj)))
                (if (not (vl-catch-all-error-p r))
                  (setq count (+ count 1))
                )
              )
            )
          )
        )
      )
    )
  )
  count
)

(defun SC3D:SAFE-LAYOUT-NAME (s / bad)
  (if (or (null s) (= s "")) (setq s "CV"))
  (setq bad '("<" ">" "/" "\\" "\"" ":" ";" "?" "*" "|" "," "=" "`"))
  (foreach c bad
    (setq s (SC3D:REPL s c "_"))
  )
  (if (> (strlen s) 200) (setq s (substr s 1 200)))
  s
)

(defun SC3D:UNIQUE-LAYOUT-NAME (base / name n)
  (setq base (SC3D:SAFE-LAYOUT-NAME base))
  (setq name base)
  (setq n 1)
  (while (SC3D:LAYOUT-EXISTS-P name)
    (setq n (+ n 1))
    (setq name (strcat base "_" (itoa n)))
  )
  name
)

(defun SC3D:NEXT-CV-NAME (/ name)
  ;; Prochain nom libre CV_1, CV_2, ... (saute les presentations deja existantes).
  (setq name nil)
  (while (null name)
    (setq *SC3D_CV_COUNTER* (+ *SC3D_CV_COUNTER* 1))
    (if (not (SC3D:LAYOUT-EXISTS-P (strcat "CV_" (itoa *SC3D_CV_COUNTER*))))
      (setq name (strcat "CV_" (itoa *SC3D_CV_COUNTER*)))
    )
  )
  name
)

(defun SC3D:DELETE-LAYOUT-VIEWPORTS (layName / ss i e ed)
  ;; Supprime la fenetre creee par defaut avec la presentation.
  ;; L'entree VIEWPORT dont l'id (69) vaut 1 represente l'espace papier lui-meme :
  ;; on la conserve toujours.
  (setq ss (ssget "_X" (list '(0 . "VIEWPORT") (cons 410 layName))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (setq ed (entget e))
        (if (and ed (/= (cdr (assoc 69 ed)) 1))
          (entdel e)
        )
        (setq i (+ i 1))
      )
    )
  )
)

(defun SC3D:VP-FREEZE-CAMS (vpEnt showLay / echo layStr)
  ;; Gel de calques propre a une fenetre via VPLAYER (fiable sous BricsCAD,
  ;; contrairement a la modification directe des entrees 331 du VIEWPORT) :
  ;; tous les calques camera de *SC3D_ALL_CV_LAYERS* (calcules par
  ;; SC3D:CMD-EXPORT, un par champ de vision - plus un joker "SC3D_CV_*" pour
  ;; les cameras sans nom) sont geles dans cette fenetre, puis seul le calque
  ;; showLay (la camera a presenter) est degele.
  ;; showLay = nil : tout reste gele (fenetre de legende).
  (setq echo (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq layStr
    (if (and (boundp '*SC3D_ALL_CV_LAYERS*) *SC3D_ALL_CV_LAYERS*)
      (SC3D:JOIN *SC3D_ALL_CV_LAYERS* ",")
      "SC3D_CV_*"
    )
  )
  (command "_.VPLAYER" "_Freeze" layStr "_Select" vpEnt "" "")
  (if showLay
    (command "_.VPLAYER" "_Thaw" showLay "_Select" vpEnt "" "")
  )
  (setvar "CMDECHO" echo)
)

(defun SC3D:VP-ZOOM (vpEnt bmin bmax mrg / id echo dx dy p1 p2)
  ;; Cadre la fenetre sur l'emprise modele bmin/bmax (mrg = marge par cote, en
  ;; fraction de l'emprise ; 0.0 = zoom exactement entre les deux extremites).
  ;; La fenetre est activee (MSPACE + CVPORT) puis un ZOOM Fenetre est applique -
  ;; methode fiable sous BricsCAD, contrairement au reglage Target/CustomScale par
  ;; l'API - avant de revenir en espace papier.
  (setq id (cdr (assoc 69 (entget vpEnt))))
  (setq dx (* mrg (SC3D:MAX 0.001 (- (car bmax) (car bmin)))))
  (setq dy (* mrg (SC3D:MAX 0.001 (- (cadr bmax) (cadr bmin)))))
  (setq p1 (list (- (car bmin) dx) (- (cadr bmin) dy) 0.0))
  (setq p2 (list (+ (car bmax) dx) (+ (cadr bmax) dy) 0.0))
  (setq echo (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.MSPACE")
  (setvar "CVPORT" id)
  ;; Les emprises sont en WCS : conversion vers l'UCS courant pour ZOOM.
  (command "_.ZOOM" "_W" (trans p1 0 1) (trans p2 0 1))
  (command "_.PSPACE")
  (setvar "CMDECHO" echo)
)

(defun SC3D:VP-SET-SHADE-OMBRE (vpEnt / id echo)
  ;; Style visuel "Ombre" dans la fenetre : MSPACE + CVPORT (comme SC3D:VP-ZOOM)
  ;; puis VSCURRENT "_Shaded" (mot-cle integre, locale-independant).
  (setq id (cdr (assoc 69 (entget vpEnt))))
  (setq echo (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.MSPACE")
  (setvar "CVPORT" id)
  (command "_.VSCURRENT" "_Shaded")
  (command "_.PSPACE")
  (setvar "CMDECHO" echo)
)

(defun SC3D:ADD-VIEWPORT (layout cx cy w h bmin bmax mrg showLay shaded / pspc vp en)
  ;; Cree une fenetre (PViewport) centree en (cx cy) sur le papier, de taille w x h,
  ;; cadree sur l'emprise modele bmin/bmax (mrg = marge de zoom par cote).
  ;; Toutes les cameras y sont gelees sauf showLay. shaded = T : style visuel "Ombre".
  (setq pspc (vla-get-Block layout))
  (setq vp (vla-AddPViewport pspc (vlax-3d-point (list cx cy 0.0)) w h))
  (vla-Display vp :vlax-true)
  (setq en (vlax-vla-object->ename vp))
  (SC3D:VP-ZOOM en bmin bmax mrg)
  (SC3D:VP-FREEZE-CAMS en showLay)
  (if shaded (SC3D:VP-SET-SHADE-OMBRE en))
  vp
)

(defun SC3D:SET-LAYOUT-PAPER (layout / r)
  ;; Regle la mise en page de la presentation : papier 630 x 297 mm (paysage),
  ;; marges de 13 mm a gauche, a droite, en haut et en bas.
  (setq r (vl-catch-all-apply 'SC3D:SET-LAYOUT-PAPER-1 (list layout)))
  (if (or (vl-catch-all-error-p r) (null r))
    (progn
      (princ "\n  -> Mise en page non reglee automatiquement : definir manuellement")
      (princ "\n     630 x 297 mm, marges 13 mm, orientation paysage.")
      nil
    )
    T
  )
)

(defun SC3D:SET-LAYOUT-PAPER-1 (layout / en ed pairs pr)
  ;; Ecriture directe des parametres de trace dans l'objet LAYOUT (codes DXF de
  ;; AcDbPlotSettings) : fiable sous BricsCAD, y compris pour un format papier
  ;; personnalise que l'imprimante ne propose pas.
  (setq en (vlax-vla-object->ename layout))
  (setq ed (entget en))
  (setq pairs
    (list
      (cons 40 *SC3D_PAGE_MARGIN*)   ;; marge gauche (mm)
      (cons 41 *SC3D_PAGE_MARGIN*)   ;; marge basse (mm)
      (cons 42 *SC3D_PAGE_MARGIN*)   ;; marge droite (mm)
      (cons 43 *SC3D_PAGE_MARGIN*)   ;; marge haute (mm)
      (cons 44 630.0)  ;; epaisseur (largeur) du papier (mm)
      (cons 45 297.0)  ;; hauteur du papier (mm)
      (cons 46 0.0)    ;; origine du trace X
      (cons 47 0.0)    ;; origine du trace Y
      (cons 72 1)      ;; unites papier : millimetres
      (cons 73 0)      ;; rotation 0 : paysage (largeur > hauteur)
    )
  )
  (foreach pr pairs
    (if (assoc (car pr) ed)
      (setq ed (subst pr (assoc (car pr) ed) ed))
      (setq ed (append ed (list pr)))
    )
  )
  (entmod ed)
  T
)

(defun SC3D:PS-RECT (layout x1 y1 x2 y2 / arr pl)
  ;; Rectangle en espace papier (cadre A4).
  (setq arr (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill arr (list x1 y1 x2 y1 x2 y2 x1 y2))
  (setq pl (vla-AddLightWeightPolyline (vla-get-Block layout) arr))
  (vla-put-Closed pl :vlax-true)
  (vla-put-Layer pl "SC3D_CADRE")
  pl
)

(defun SC3D:PS-TEXT (layout x y h txt / mt)
  ;; Texte en espace papier, centre sur (x y).
  (setq mt (vla-AddMText (vla-get-Block layout) (vlax-3d-point (list x y 0.0)) 0.0 txt))
  (vla-put-Height mt h)
  (vla-put-AttachmentPoint mt 5) ;; centre
  (vla-put-InsertionPoint mt (vlax-3d-point (list x y 0.0)))
  (vla-put-Layer mt "SC3D_CADRE")
  mt
)

(defun SC3D:DRAW-A4-FRAMES (layout cw uh)
  ;; Trois cadres cote a cote, entierement DANS la zone imprimable (l'origine
  ;; (0,0) de l'espace papier est au coin de cette zone) : chaque volet fait un
  ;; tiers de la zone utile.
  (SC3D:LAYER "SC3D_CADRE" 7)
  (SC3D:PS-RECT layout 0.0 0.0 cw uh)
  (SC3D:PS-RECT layout cw 0.0 (* 2.0 cw) uh)
  (SC3D:PS-RECT layout (* 2.0 cw) 0.0 (* 3.0 cw) uh)
)

(defun SC3D:EXPORT-MAKE-LAYOUT (baseName legendBox existRec projRec camMrg / doc name layout uw uh cw vpW vpH midY titY infoY sitE lblE lw lh k lvW lvH evVals pvVals)
  ;; Cree une presentation en 3 volets, ENTIEREMENT dans la zone imprimable
  ;; (papier 630 x 297 paysage, marges 13 mm -> zone utile 604 x 271 ; l'origine
  ;; (0,0) de l'espace papier correspond au coin de cette zone) :
  ;;   volet 1 : legende (toutes les cameras gelees)
  ;;   volet 2 : situation existante (ou camera seule) - toutes les autres gelees
  ;;   volet 3 : situation projetee, cadree sur son propre champ de vision
  ;; Les cadres, les titres et les fenetres restent tous dans la zone imprimable.
  (setq doc (SC3D:ACAD-DOC))
  (setq name (SC3D:UNIQUE-LAYOUT-NAME baseName))
  (setq layout (vla-Add (vla-get-Layouts doc) name))

  ;; Marque cette presentation comme generee par l'export, pour pouvoir la
  ;; reconnaitre et la supprimer automatiquement lors d'un export ulterieur
  ;; (cf. SC3D:DELETE-EXPORT-LAYOUTS).
  (SC3D:SET-XDATA (vlax-vla-object->ename layout) "1")

  ;; L'activation de la presentation peut creer la fenetre par defaut : on la supprime.
  (setvar "CTAB" name)
  (SC3D:DELETE-LAYOUT-VIEWPORTS name)

  ;; Mise en page : papier 630 x 297 paysage, marges 13 mm.
  (SC3D:SET-LAYOUT-PAPER layout)

  ;; Zone imprimable et largeur d'un volet (un tiers de la zone utile).
  (setq uw (- 630.0 (* 2.0 *SC3D_PAGE_MARGIN*)))
  (setq uh (- 297.0 (* 2.0 *SC3D_PAGE_MARGIN*)))
  (setq cw (/ uw 3.0))

  (SC3D:DRAW-A4-FRAMES layout cw uh)

  ;; Fenetres : marge interieure de 10 mm, plus une bande de 8 mm reservee en
  ;; haut de chaque volet pour le titre.
  (setq vpW (- cw (* 2.0 *SC3D_VP_MARGIN*)))
  (setq vpH (- uh (* 2.0 *SC3D_VP_MARGIN*) 8.0))
  (setq midY (+ *SC3D_VP_MARGIN* (/ vpH 2.0)))
  (setq titY (- uh 6.0))
  (setq infoY (/ *SC3D_VP_MARGIN* 2.0))

  ;; Titres des volets, dans la bande superieure de la zone imprimable.
  (setq sitE (cdr (assoc 'sit existRec)))
  (setq lblE
    (cond
      (projRec "Situation existante")
      ((= sitE "EXIST") "Situation existante")
      ((= sitE "PROJ") "Situation projet\\U+00E9e")
      (T nil)
    )
  )
  (if lblE
    (SC3D:PS-TEXT layout (* 1.5 cw) titY 5.0 (strcat lblE " - " baseName))
  )
  (if projRec
    (SC3D:PS-TEXT layout (* 2.5 cw) titY 5.0 (strcat "Situation projet\\U+00E9e - " baseName))
  )

  ;; Volet 1 : legende. La fenetre est dimensionnee aux memes proportions que la
  ;; zone choisie (la plus grande possible dans le volet) : la legende remplit
  ;; ainsi TOUTE la fenetre, bord a bord, sans bande vide.
  (if legendBox
    (progn
      (setq lw (- (car (cadr legendBox)) (car (car legendBox))))
      (setq lh (- (cadr (cadr legendBox)) (cadr (car legendBox))))
      (if (< lw 0.001) (setq lw 0.001))
      (if (< lh 0.001) (setq lh 0.001))
      (setq k (SC3D:MIN (/ vpW lw) (/ vpH lh)))
      (setq lvW (* k lw))
      (setq lvH (* k lh))
      (SC3D:ADD-VIEWPORT layout
        (/ cw 2.0) midY
        lvW lvH
        (car legendBox) (cadr legendBox)
        0.0
        nil
        nil
      )
    )
  )

  ;; Volet 2 : situation existante (ou camera seule) : seul son calque reste degele.
  (SC3D:ADD-VIEWPORT layout
    (* 1.5 cw) midY
    vpW vpH
    (cdr (assoc 'bmin existRec)) (cdr (assoc 'bmax existRec))
    camMrg
    (cdr (assoc 'lay existRec))
    T
  )

  ;; Sous la fenetre : modele, capteur, focale, definition et angle de la camera.
  (setq evVals (cdr (assoc 'vals existRec)))
  (if evVals
    (SC3D:PS-TEXT layout (* 1.5 cw) infoY 2.75 (SC3D:CAM-INFO-TEXT evVals))
  )

  ;; Volet 3 : situation projetee, cadree sur SON emprise, a l'endroit ou elle est
  ;; dans le dessin : seul le calque de la projetee reste degele (l'existante et
  ;; toutes les autres cameras sont cachees dans cette fenetre).
  (if projRec
    (progn
      (SC3D:ADD-VIEWPORT layout
        (* 2.5 cw) midY
        vpW vpH
        (cdr (assoc 'bmin projRec)) (cdr (assoc 'bmax projRec))
        camMrg
        (cdr (assoc 'lay projRec))
        T
      )
      (setq pvVals (cdr (assoc 'vals projRec)))
      (if pvVals
        (SC3D:PS-TEXT layout (* 2.5 cw) infoY 2.75 (SC3D:CAM-INFO-TEXT pvVals))
      )
    )
  )

  (princ (strcat "\nPresentation creee : " name))
  name
)

(defun SC3D:FIND-SIT-REC (lst sit / found)
  (foreach r lst
    (if (and (null found) (= (cdr (assoc 'sit r)) sit))
      (setq found r)
    )
  )
  found
)

(defun SC3D:EXPORT-SINGLE (rec legendBox camMrg / base)
  (setq base (cdr (assoc 'name rec)))
  (if (or (null base) (= base ""))
    (setq base (SC3D:NEXT-CV-NAME))
  )
  (SC3D:EXPORT-MAKE-LAYOUT base legendBox rec nil camMrg)
)

(defun SC3D:CMD-EXPORT (/ selEnts allEnts recs r e p1 p2 w1 w2 legendBox pct camMrg groups key grp lst existR projR curtab cfg vals delChoix delCount)
  (setq curtab (getvar "CTAB"))
  (if (/= curtab "Model")
    (princ "\nExport a lancer depuis l'espace objet (Model).")
    (progn
      (princ "\nSelectionner les cameras a exporter : ")
      (setq selEnts (SC3D:SSGET-CAMERAS nil))

      (if (null selEnts)
        (princ "\nAucun bloc camera selectionne.")
        (progn
          ;; Zone de legende (optionnelle), choisie dans le dessin. Elle sera affichee
          ;; dans le 1er A4 de chaque presentation.
          (setq legendBox nil)
          (setq p1 (getpoint "\nPremier coin de la zone de legende <Entree = pas de legende> : "))
          (if p1
            (progn
              (setq p2 (getcorner p1 "\nCoin oppose de la zone de legende : "))
              (if p2
                (progn
                  (setq w1 (SC3D:UCS-PT->WCS p1))
                  (setq w2 (SC3D:UCS-PT->WCS p2))
                  (setq legendBox
                    (list
                      (list (SC3D:MIN (car w1) (car w2)) (SC3D:MIN (cadr w1) (cadr w2)) 0.0)
                      (list (SC3D:MAX (car w1) (car w2)) (SC3D:MAX (cadr w1) (cadr w2)) 0.0)
                    )
                  )
                )
              )
            )
          )

          ;; Zoom souhaite sur les cameras : marge autour de l'emprise du champ de
          ;; vision, en % (0 = champ au plus pres ; plus la valeur est grande, plus
          ;; on voit de choses autour). Memorise pour l'export suivant.
          (setq pct
            (getreal
              (strcat
                "\nMarge de zoom autour des champs de vision en % <"
                (rtos *SC3D_EXPORT_ZOOM* 2 0)
                "> : "
              )
            )
          )
          (if (null pct) (setq pct *SC3D_EXPORT_ZOOM*))
          (if (< pct 0.0) (setq pct 0.0))
          (setq *SC3D_EXPORT_ZOOM* pct)
          (setq camMrg (/ pct 200.0))

          ;; Nettoyage optionnel des presentations d'un export precedent (reperees
          ;; par leur xdata, cf. SC3D:DELETE-EXPORT-LAYOUTS) : les presentations
          ;; propres a l'utilisateur ne sont jamais touchees.
          (initget "Oui Non")
          (setq delChoix
            (getkword "\nSupprimer les presentations d'un export precedent ? [Oui/Non] <Non> : ")
          )
          (if (= delChoix "Oui")
            (progn
              (setq delCount (SC3D:DELETE-EXPORT-LAYOUTS))
              (princ (strcat "\n" (itoa delCount) " presentation(s) supprimee(s)."))
            )
          )

          ;; Toutes les cameras du dessin (selectionnees ou non) recoivent leur propre
          ;; calque (nom du champ de vision + situation, ou SC3D_CV_<handle> si le
          ;; champ n'a pas de nom) : dans chaque fenetre, tous ces calques sont geles
          ;; (liste dans *SC3D_ALL_CV_LAYERS*, cf. SC3D:VP-FREEZE-CAMS), sauf celui
          ;; de la camera presentee.
          (setq allEnts (SC3D:SSGET-CAMERAS "_X"))
          (setq *SC3D_ALL_CV_LAYERS* '())
          (foreach e allEnts
            (setq cfg (SC3D:GET-XDATA e))
            (setq vals (if cfg (SC3D:CFG-VALS cfg) nil))
            (if vals
              (setq *SC3D_ALL_CV_LAYERS*
                (append *SC3D_ALL_CV_LAYERS* (list (SC3D:CAM-LAYER-ASSIGN e vals)))
              )
            )
          )

          (setq recs '())
          (foreach e selEnts
            (setq r (SC3D:CAM-REC e))
            (if r (setq recs (append recs (list r))))
          )

          (setq *SC3D_CV_COUNTER* 0)

          ;; Regroupement par nom de champ de vision (insensible a la casse).
          (setq groups '())
          (foreach r recs
            (setq key (strcase (cdr (assoc 'name r))))
            (setq grp (assoc key groups))
            (if grp
              (setq groups (subst (cons key (append (cdr grp) (list r))) grp groups))
              (setq groups (append groups (list (cons key (list r)))))
            )
          )

          (foreach grp groups
            (setq key (car grp))
            (setq lst (cdr grp))
            (if (= key "")
              ;; Cameras sans nom : une presentation CV_n chacune.
              (foreach r lst (SC3D:EXPORT-SINGLE r legendBox camMrg))
              (progn
                (setq existR (SC3D:FIND-SIT-REC lst "EXIST"))
                (setq projR (SC3D:FIND-SIT-REC lst "PROJ"))
                (if (and existR projR)
                  (progn
                    ;; Meme nom + une existante et une projetee :
                    ;; presentation combinee existante (2e A4) / projetee (3e A4).
                    (SC3D:EXPORT-MAKE-LAYOUT
                      (cdr (assoc 'name existR))
                      legendBox
                      existR
                      projR
                      camMrg
                    )
                    ;; Les eventuelles autres cameras du meme nom : une presentation chacune.
                    (foreach r lst
                      (if (and (not (equal r existR)) (not (equal r projR)))
                        (SC3D:EXPORT-SINGLE r legendBox camMrg)
                      )
                    )
                  )
                  ;; Pas de paire existante/projetee : une presentation par camera.
                  (foreach r lst (SC3D:EXPORT-SINGLE r legendBox camMrg))
                )
              )
            )
          )

          (setvar "CTAB" "Model")
          (command "_.REGEN")
          (princ "\nExport termine.")
        )
      )
    )
  )
  (princ)
)

(defun SC3D:MENU-CAMERA (/ choix)
  (initget "C M L J A S T V E")
  (setq choix
    (getkword
      "\nCamera - action [Creer/Modifier/caLculer/aJuster/Ajouter/Supprimer/Texte/Visibilite/Exporter] <C> : "
    )
  )
  (if (null choix)
    (setq choix "C")
  )
  choix
)

(defun c:S_CAMERA (/ choix)
  (setq choix (SC3D:MENU-CAMERA))

  (cond
    ((= choix "C")
      (SC3D:CMD-CREER)
    )
    ((= choix "M")
      (SC3D:CMD-MODIFIER)
    )
    ((= choix "L")
      (SC3D:CMD-CALCULER)
    )
    ((= choix "J")
      (SC3D:CMD-AJUSTER)
    )
    ((= choix "A")
      (SC3D:CMD-AJOUTER)
    )
    ((= choix "S")
      (SC3D:CMD-SUPPRIMER)
    )
    ((= choix "T")
      (SC3D:CMD-GENERER-TEXTE)
    )
    ((= choix "V")
      (SC3D:CMD-VISIBILITE)
    )
    ((= choix "E")
      (SC3D:CMD-EXPORT)
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ C_S_IA_IMAGE_VECTEUR ------------------------------------------------------------------------------------

;; ============================================================
;; OUTILS GENERAUX
;; ============================================================

(defun SIA:GetDocumentsPath (/ sh folders path)
  (setq sh (vlax-create-object "WScript.Shell"))
  (setq folders (vlax-get sh 'SpecialFolders))
  (setq path (vlax-invoke folders 'Item "MyDocuments"))
  (vlax-release-object sh)
  path
)

(defun SIA:EnsureFolder (folder)
  (if (not (vl-file-directory-p folder))
    (vl-mkdir folder)
  )
)

(defun SIA:ValidString (s)
  (and s (= (type s) 'STR) (> (strlen s) 0))
)

(defun SIA:Trim (s)
  (if (SIA:ValidString s)
    (vl-string-trim " \t\r\n" s)
    ""
  )
)

(defun SIA:ReplaceAll (s old new / pos)
  (while (setq pos (vl-string-search old s))
    (setq s
      (strcat
        (substr s 1 pos)
        new
        (substr s (+ pos (strlen old) 1))
      )
    )
  )
  s
)

(defun SIA:Quote (s)
  (strcat "\"" s "\"")
)

(defun SIA:BatQuote (s)
  ;; Pour CMD/BAT : accepte les chemins avec espaces
  (strcat "\"" (SIA:ReplaceAll s "\"" "\"\"") "\"")
)

(defun SIA:PSQuote (s)
  ;; Pour PowerShell
  (strcat "'" (SIA:ReplaceAll s "'" "''") "'")
)

(defun SIA:IsAbsolutePath (p)
  (and
    (SIA:ValidString p)
    (or
      (wcmatch p "?:\\*")
      (wcmatch p "?:/*")
      (wcmatch p "\\\\*")
    )
  )
)

(defun SIA:ResolvePath (p / dwgdir)
  (cond
    ((not (SIA:ValidString p)) nil)
    ((SIA:IsAbsolutePath p) p)
    (T
      (setq dwgdir (getvar "DWGPREFIX"))
      (if (SIA:ValidString dwgdir)
        (strcat dwgdir p)
        p
      )
    )
  )
)

(defun SIA:Split (s sep / pos item result)
  (setq result nil)

  (while (setq pos (vl-string-search sep s))
    (setq item (substr s 1 pos))
    (setq result (cons item result))
    (setq s (substr s (+ pos (strlen sep) 1)))
  )

  (setq result (cons s result))
  (reverse result)
)

(defun SIA:CountCombinations (comboStr / parts p n)
  (setq n 0)
  (setq parts (SIA:Split comboStr ";"))

  (foreach p parts
    (if (> (strlen (SIA:Trim p)) 0)
      (setq n (1+ n))
    )
  )

  n
)

(defun SIA:WriteLinesToFile (filePath lines / f line)
  (setq f (open filePath "w"))

  (if f
    (progn
      (foreach line lines
        (write-line line f)
      )
      (close f)
      T
    )
    nil
  )
)

;; ============================================================
;; GESTION DXF
;; ============================================================

(defun SIA:BuildDXFList (imagePath count / imgDir imgBase i suffix dxfPath result)
  (setq imgDir (vl-filename-directory imagePath))
  (setq imgBase (vl-filename-base imagePath))
  (setq i 1)
  (setq result nil)

  (while (<= i count)
    (setq suffix
      (if (= i 1)
        ""
        (strcat "_" (itoa i))
      )
    )

    (setq dxfPath (strcat imgDir "\\" imgBase suffix ".dxf"))
    (setq result (cons (list i dxfPath) result))
    (setq i (1+ i))
  )

  (reverse result)
)

(defun SIA:AnyDXFExists (dxfList / found item)
  (setq found nil)

  (foreach item dxfList
    (if (findfile (cadr item))
      (setq found T)
    )
  )

  found
)

(defun SIA:DeleteExistingDXFs (dxfList / item p)
  (foreach item dxfList
    (setq p (cadr item))
    (if (findfile p)
      (vl-file-delete p)
    )
  )
)

(defun SIA:PrintDXFList (dxfList / item)
  (foreach item dxfList
    (princ
      (strcat
        "\nDXF "
        (itoa (car item))
        " attendu : "
        (cadr item)
      )
    )
  )
)

(defun SIA:GetDXFByNumber (dxfList num / found item)
  (setq found nil)

  (foreach item dxfList
    (if (= (car item) num)
      (setq found (cadr item))
    )
  )

  found
)

;; ============================================================
;; SELECTION IMAGE DEPUIS UN FICHIER
;; ============================================================

(defun SIA:GetImagePathFromFileDialog (/ path)
  ;; Ouvre directement une fenetre Windows pour choisir l'image source.
  ;; Ne cherche plus a selectionner/identifier une image inseree dans BricsCAD.
  (setq path
    (getfiled
      "Choisir l'image a vectoriser"
      ""
      "png;jpg;jpeg;bmp;tif;tiff;webp"
      0
    )
  )

  (if (SIA:ValidString path)
    (progn
      (setq path (SIA:ResolvePath path))
      (princ (strcat "
Image source utilisee : " path))
      path
    )
    nil
  )
)

;; ============================================================
;; TELECHARGEMENT VECTORIZER.EXE
;; ============================================================

(defun SIA:DownloadVectorizer (exePath / url ps cmd shell ret)
  (setq url "https://github.com/dawson-ald/sncf-briscad/releases/download/v1.0/vectorizer.exe")

  (setq ps
    (strcat
      "$ProgressPreference='SilentlyContinue'; "
      "Write-Host 'Telechargement de vectorizer.exe...'; "
      "Invoke-WebRequest -Uri "
      (SIA:PSQuote url)
      " -OutFile "
      (SIA:PSQuote exePath)
      "; "
      "Write-Host 'Telechargement termine.'; "
      "pause"
    )
  )

  (setq cmd
    (strcat
      "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
      (SIA:Quote ps)
    )
  )

  (princ "\nTelechargement de vectorizer.exe via PowerShell...")

  (setq shell (vlax-create-object "WScript.Shell"))
  (setq ret (vlax-invoke shell 'Run cmd 1 :vlax-true))
  (vlax-release-object shell)

  (if (findfile exePath)
    T
    nil
  )
)

;; ============================================================
;; EXECUTION DU VECTORISEUR
;; ============================================================

(defun SIA:RunVectorizer (exePath imagePath combinationsArg / tmpDir batPath lines shell ret)

  (setq tmpDir (getenv "TEMP"))

  (if (not (SIA:ValidString tmpDir))
    (setq tmpDir (getvar "TEMPPREFIX"))
  )

  (setq batPath
    (strcat
      tmpDir
      "\\s_ia_vectorizer_"
      (rtos (* 1000000.0 (getvar "DATE")) 2 0)
      ".bat"
    )
  )

  (setq lines
    (list
      "@echo off"
      "chcp 65001 >nul"
      "echo Lancement de la vectorisation..."
      (strcat "echo Image : " imagePath)
      (strcat "echo Combinaisons : " combinationsArg)
      "echo."
      (strcat
        (SIA:BatQuote exePath)
        " "
        (SIA:BatQuote imagePath)
        " "
        (SIA:BatQuote combinationsArg)
      )
      "set ERR=%ERRORLEVEL%"
      "echo."
      "if %ERR%==0 ("
      "  echo Vectorisation terminee."
      ") else ("
      "  echo Erreur vectorizer.exe, code : %ERR%"
      ")"
      "echo."
      "echo Fermez cette fenetre pour revenir a BricsCAD."
      "pause"
      "exit /b %ERR%"
    )
  )

  (if (not (SIA:WriteLinesToFile batPath lines))
    (progn
      (princ "\nErreur : impossible de creer le fichier BAT temporaire.")
      1
    )
    (progn
      (princ "\nLancement de vectorizer.exe...")
      (princ (strcat "\nBAT temporaire : " batPath))

      (setq shell (vlax-create-object "WScript.Shell"))

      (setq ret
        (vlax-invoke
          shell
          'Run
          (SIA:BatQuote batPath)
          1
          :vlax-true
        )
      )

      (vlax-release-object shell)

      ret
    )
  )
)

;; ============================================================
;; IMPORT DXF MODIFIABLE
;; ============================================================

(defun SIA:ExplodeLastInsert (/ ent ed)
  (setq ent (entlast))

  (if ent
    (progn
      (setq ed (entget ent))

      (if (= (cdr (assoc 0 ed)) "INSERT")
        (progn
          (command "_.EXPLODE" ent)
          (princ "\nBloc DXF explose : les elements sont maintenant modifiables.")
        )
        (princ "\nLe dernier objet insere n'est pas un bloc INSERT.")
      )
    )
  )
)

(defun SIA:InsertDXFEditable (dxfPath / pt oldEcho oldFileDia oldCmddia)
  (if (findfile dxfPath)
    (progn
      (setq pt (getpoint "\nPoint d'insertion du DXF : "))

      (if pt
        (progn
          (setq oldEcho (getvar "CMDECHO"))
          (setq oldFileDia (getvar "FILEDIA"))
          (setq oldCmddia (getvar "CMDDIA"))

          (setvar "CMDECHO" 0)
          (setvar "FILEDIA" 0)
          (setvar "CMDDIA" 0)

          ;; Chemin DXF protege avec guillemets pour accepter les espaces
          (command "_.-INSERT" (SIA:BatQuote dxfPath) pt "1" "1" "0")

          (SIA:ExplodeLastInsert)

          (setvar "CMDECHO" oldEcho)
          (setvar "FILEDIA" oldFileDia)
          (setvar "CMDDIA" oldCmddia)

          (princ "\nDXF insere en objets modifiables.")
        )
        (princ "\nInsertion annulee.")
      )
    )
    (princ "\nErreur : fichier DXF introuvable.")
  )
)

;; ============================================================
;; COMMANDE PRINCIPALE
;; ============================================================

(defun c:S_IA_IMAGE_VECTEUR
  (/ docs bricscadFolder exePath imagePath combinationsArg comboCount dxfList rep dlOk ret dxfPath choice)

  (vl-load-com)

  (setq docs (SIA:GetDocumentsPath))
  (setq bricscadFolder (strcat docs "\\BricsCAD"))
  (setq exePath (strcat bricscadFolder "\\vectorizer.exe"))

  (SIA:EnsureFolder bricscadFolder)

  (setq imagePath (SIA:GetImagePathFromFileDialog))

  (if (not (SIA:ValidString imagePath))
    (progn
      (princ "\nCommande annulee : aucun chemin image valide.")
      (princ)
      (exit)
    )
  )

  (if (not (findfile imagePath))
    (progn
      (princ "\nErreur : le fichier image source est introuvable :")
      (princ (strcat "\n" imagePath))
      (princ)
      (exit)
    )
  )

  (if (not (findfile exePath))
    (progn
      (initget "Oui Non")
      (setq rep
        (getkword
          "\nvectorizer.exe est introuvable dans Documents\\BricsCAD. Voulez-vous le telecharger ? [Oui/Non] <Oui> : "
        )
      )

      (if (or (null rep) (= rep "Oui"))
        (progn
          (setq dlOk (SIA:DownloadVectorizer exePath))

          (if (not dlOk)
            (progn
              (princ "\nErreur : impossible de telecharger vectorizer.exe.")
              (princ)
              (exit)
            )
          )
        )
        (progn
          (princ "\nOperation annulee : vectorizer.exe manquant.")
          (princ)
          (exit)
        )
      )
    )
  )

  ;; Valeur par defaut :
  ;; vectorizer.exe "C:\Chemin\Image 1.png" "3, 1; 3, 2; 0, 2"
  (setq combinationsArg
    (getstring T
      "\nCombinaisons model, algo <3, 1; 3, 2; 0, 2> : "
    )
  )

  (if (= (SIA:Trim combinationsArg) "")
    (setq combinationsArg "3, 1; 3, 2; 0, 2")
  )

  (setq comboCount (SIA:CountCombinations combinationsArg))

  (if (< comboCount 1)
    (progn
      (princ "\nErreur : aucune combinaison valide.")
      (princ)
      (exit)
    )
  )

  (setq dxfList (SIA:BuildDXFList imagePath comboCount))

  (princ "\nFichiers DXF attendus :")
  (SIA:PrintDXFList dxfList)

  ;; Supprime les anciens DXF attendus pour eviter une fausse detection
  (SIA:DeleteExistingDXFs dxfList)

  ;; Lance vectorizer.exe avec chemins proteges
  (setq ret (SIA:RunVectorizer exePath imagePath combinationsArg))

  (if (/= ret 0)
    (progn
      (princ "\nAttention : vectorizer.exe a retourne une erreur.")
      (princ "\nVerification des DXF generes quand meme...")
    )
  )

  (if (not (SIA:AnyDXFExists dxfList))
    (progn
      (princ "\nAucun DXF trouve apres vectorisation.")
      (princ "\nFichiers attendus :")
      (SIA:PrintDXFList dxfList)
      (princ)
      (exit)
    )
  )

  (while T
    (setq rep
      (getstring T
        (strcat
          "\nQuel DXF inserer en objets modifiables ? Numero 1-"
          (itoa comboCount)
          " ou Q pour quitter <1> : "
        )
      )
    )

    (setq rep (SIA:Trim rep))

    (cond
      ((= rep "")
        (setq choice 1)
        (setq dxfPath (SIA:GetDXFByNumber dxfList choice))

        (if (findfile dxfPath)
          (SIA:InsertDXFEditable dxfPath)
          (princ "\nCe DXF est introuvable.")
        )
      )

      ((or (= (strcase rep) "Q") (= (strcase rep) "QUITTER"))
        (princ "\nCommande terminee.")
        (princ)
        (exit)
      )

      (T
        (setq choice (atoi rep))
        (setq dxfPath (SIA:GetDXFByNumber dxfList choice))

        (if dxfPath
          (if (findfile dxfPath)
            (SIA:InsertDXFEditable dxfPath)
            (princ "\nCe DXF est introuvable.")
          )
          (princ "\nChoix invalide.")
        )
      )
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ C_S_LOGO ------------------------------------------------------------------------------------

;; ------------------------------------------------------------------------------------
;; C_S_LOGO
;; Config globale : Documents\BricsCAD\logo.config
;; Format config : NomLogo|URL
;; ------------------------------------------------------------------------------------

(defun ps-escape (s /)
  (vl-string-subst "''" "'" s)
)

(defun random-logo-name (/ d n)
  (setq d (getvar "DATE"))
  (setq n (rem (fix (* 1000000000 (- d (fix d)))) 1000000))
  (strcat "logo_" (itoa n))
)

(defun clean-filename (name / badchars ch)
  (setq badchars '("\\" "/" ":" "*" "?" "\"" "<" ">" "|"))

  (foreach ch badchars
    (while (vl-string-search ch name)
      (setq name (vl-string-subst "_" ch name))
    )
  )

  name
)

(defun make-layer (name color /)
  (if (not (tblsearch "LAYER" name))
    (command "_.LAYER" "_M" name "_C" color name "")
  )
)

(defun logo-is-url (s / u)
  (setq u (strcase s))

  (or
    (wcmatch u "HTTP://*")
    (wcmatch u "HTTPS://*")
  )
)

(defun get-url-extension (url / u qpos)
  (setq u (strcase url))
  (setq qpos (vl-string-search "?" u))

  (if qpos
    (setq u (substr u 1 qpos))
  )

  (cond
    ((wcmatch u "*.PNG") ".png")
    ((wcmatch u "*.JPG") ".jpg")
    ((wcmatch u "*.JPEG") ".jpg")
    ((wcmatch u "*.WEBP") ".webp")
    (T ".png")
  )
)

(defun filename-has-extension (name / u)
  (setq u (strcase name))

  (or
    (wcmatch u "*.PNG")
    (wcmatch u "*.JPG")
    (wcmatch u "*.JPEG")
    (wcmatch u "*.WEBP")
  )
)

;; ------------------------------------------------------------------------------------
;; DOSSIER CONFIG GLOBAL
;; Documents\BricsCAD\logo.config
;; ------------------------------------------------------------------------------------

(defun get-bricscad-config-folder (/ userprofile folder)
  (setq userprofile (getenv "USERPROFILE"))

  (if (or (null userprofile) (= userprofile ""))
    (setq userprofile (getvar "DWGPREFIX"))
  )

  (setq folder (strcat userprofile "\\Documents\\BricsCAD\\"))

  (if (not (vl-file-directory-p folder))
    (vl-mkdir folder)
  )

  folder
)

(defun get-logo-config-file (/)
  (strcat (get-bricscad-config-folder) "logo.config")
)

;; ------------------------------------------------------------------------------------
;; DOSSIER LOCAL DES IMAGES
;; ------------------------------------------------------------------------------------

(defun get-logo-basefolder (/ basefolder folder)
  (setq basefolder (getvar "DWGPREFIX"))

  (if (= basefolder "")
    (setq basefolder (strcat (getenv "USERPROFILE") "\\Documents\\"))
  )

  (setq folder (strcat basefolder "logos\\"))

  (if (not (vl-file-directory-p folder))
    (vl-mkdir folder)
  )

  folder
)

;; ------------------------------------------------------------------------------------
;; TELECHARGEMENT IMAGE
;; ------------------------------------------------------------------------------------

(defun download-logo-url (url filepath / sh cmd result)
  (vl-load-com)

  (setq sh (vlax-create-object "WScript.Shell"))

  (setq cmd
    (strcat
      "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
      "\""
      "$ErrorActionPreference='Stop'; "
      "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; "
      "$url='" (ps-escape url) "'; "
      "$out='" (ps-escape filepath) "'; "
      "$folder=Split-Path $out; "
      "if (!(Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }; "
      "$ua='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36'; "
      "$wc=New-Object System.Net.WebClient; "
      "$wc.Proxy=[System.Net.WebRequest]::GetSystemWebProxy(); "
      "$wc.Proxy.Credentials=[System.Net.CredentialCache]::DefaultNetworkCredentials; "
      "$wc.Headers.Add('User-Agent',$ua); "
      "$wc.Headers.Add('Accept','image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8'); "
      "$wc.Headers.Add('Accept-Language','fr-FR,fr;q=0.9,en;q=0.8'); "
      "$wc.Headers.Add('Referer','https://www.google.com/'); "
      "$wc.DownloadFile($url,$out); "
      "if (!(Test-Path $out)) { exit 1 }; "
      "if ((Get-Item $out).Length -le 0) { exit 1 }; "
      "exit 0"
      "\""
    )
  )

  (setq result (vlax-invoke sh 'Run cmd 0 :vlax-true))
  (vlax-release-object sh)

  (= result 0)
)

(defun download-logo-to-dwg-folder (name url / folder ext filename filepath ok)
  (setq folder (get-logo-basefolder))
  (setq name (clean-filename name))
  (setq ext (get-url-extension url))

  (if (filename-has-extension name)
    (setq filename name)
    (setq filename (strcat name ext))
  )

  (setq filepath (strcat folder filename))

  ;; A chaque insertion, on retelecharge depuis l'URL
  (if (findfile filepath)
    (vl-file-delete filepath)
  )

  (setq ok (download-logo-url url filepath))

  (if (and ok (findfile filepath))
    filepath
    nil
  )
)


(defun logo-config-line-name (line / p)
  (setq p (vl-string-search "|" line))

  (if p
    (substr line 1 p)
    nil
  )
)

(defun logo-config-line-url (line / p)
  (setq p (vl-string-search "|" line))

  (if p
    (substr line (+ p 2))
    nil
  )
)

(defun logo-config-read (/ file f line data name url)
  (setq file (get-logo-config-file))
  (setq data nil)

  (if (findfile file)
    (progn
      (setq f (open file "r"))

      (while (setq line (read-line f))
        (setq name (logo-config-line-name line))
        (setq url (logo-config-line-url line))

        (if
          (and
            name
            url
            (/= name "")
            (/= url "")
            (logo-is-url url)
          )
          (setq data (cons (cons name url) data))
        )
      )

      (close f)
    )
  )

  (reverse data)
)

(defun logo-config-get (name / data item result)
  (setq data (logo-config-read))
  (setq result nil)

  (foreach item data
    (if (= (strcase (car item)) (strcase name))
      (setq result item)
    )
  )

  result
)

(defun logo-config-remove (name / data newdata item)
  (setq data (logo-config-read))
  (setq newdata nil)

  (foreach item data
    (if (/= (strcase (car item)) (strcase name))
      (setq newdata (cons item newdata))
    )
  )

  (reverse newdata)
)

(defun logo-config-write-all (data / file f item)
  (setq file (get-logo-config-file))
  (setq f (open file "w"))

  (foreach item data
    (write-line
      (strcat
        (car item)
        "|"
        (cdr item)
      )
      f
    )
  )

  (close f)
)

(defun logo-config-add (name url / data)
  ;; Supprime l'ancien logo du meme nom, puis ajoute le nouveau
  (setq data (logo-config-remove name))
  (setq data (append data (list (cons name url))))
  (logo-config-write-all data)
)

(defun logo-config-delete (name / data newdata deleted item)
  (setq data (logo-config-read))
  (setq newdata nil)
  (setq deleted nil)

  (foreach item data
    (if (= (strcase (car item)) (strcase name))
      (setq deleted T)
      (setq newdata (cons item newdata))
    )
  )

  (if deleted
    (progn
      (logo-config-write-all (reverse newdata))
      T
    )
    nil
  )
)

(defun logo-config-print (/ data item)
  (setq data (logo-config-read))

  (if data
    (progn
      (princ "\n\nLogos disponibles :")

      (foreach item data
        (princ (strcat "\n- " (car item)))
      )
    )
    (princ "\nAucun logo enregistre dans la bibliotheque.")
  )

  (princ)
)

(defun add-logo-url-to-library (url imgname / filepath)
  (vl-load-com)

  (setq imgname (clean-filename imgname))

  (if (= imgname "")
    (setq imgname (random-logo-name))
  )

  (if (not (logo-is-url url))
    (progn
      (princ "\nErreur : la bibliotheque accepte uniquement des URL.")
      nil
    )
    (progn
      ;; Telechargement dans le DWG courant
      ;; Mais logo.config garde seulement Nom|URL
      (setq filepath (download-logo-to-dwg-folder imgname url))

      (if filepath
        (progn
          (logo-config-add imgname url)

          (princ "\nImage ajoutee a la bibliotheque.")
          (princ (strcat "\nNom : " imgname))
          (princ (strcat "\nURL : " url))
          (princ (strcat "\nFichier telecharge : " filepath))
          (princ (strcat "\nConfig : " (get-logo-config-file)))

          filepath
        )
        (progn
          (princ "\nErreur : impossible de telecharger l'image.")
          nil
        )
      )
    )
  )
)

(defun delete-logo-from-library (/ imgname ok)
  (logo-config-print)

  (setq imgname
    (getstring T "\n\nEntrer le nom exact du logo a supprimer : ")
  )

  (if (or (null imgname) (= imgname ""))
    (progn
      (princ "\nErreur : aucun nom indique.")
      nil
    )
    (progn
      (setq ok (logo-config-delete imgname))

      (if ok
        (progn
          (princ "\nLogo supprime de la bibliotheque.")
          (princ (strcat "\nNom : " imgname))
          T
        )
        (progn
          (princ "\nErreur : ce logo n'existe pas dans la bibliotheque.")
          nil
        )
      )
    )
  )
)

(defun apply-image-transparency (ent /)
  (if ent
    (progn
      (command "_.TRANSPARENCY" ent "" "_ON")
    )
  )

  ent
)

;; ------------------------------------------------------------------------------------
;; INSERTION IMAGE
;; ------------------------------------------------------------------------------------

(defun insert-logo-from-file (filepath pt largeur rotation layer / ent)
  (vl-load-com)

  (if (not (tblsearch "LAYER" layer))
    (make-layer layer 7)
  )

  (if (not (findfile filepath))
    (progn
      (princ "\nErreur : le fichier image est introuvable.")
      nil
    )
    (progn
      (command "_.LAYER" "_S" layer "")
      (command "_.IMAGEATTACH" filepath pt largeur rotation)

      (setq ent (entlast))

      ;; Correction fond noir / transparence
      (apply-image-transparency ent)

      (princ "\nLogo insere avec succes.")
      (princ (strcat "\nFichier : " filepath))

      ent
    )
  )
)

(defun insert-logo-from-url (url imgname pt largeur rotation layer / filepath)
  ;; A chaque insertion, on retelecharge dans le dossier du DWG\logos\
  (setq filepath (download-logo-to-dwg-folder imgname url))

  (if filepath
    (insert-logo-from-file filepath pt largeur rotation layer)
    (princ "\nErreur : impossible de telecharger le logo depuis l'URL.")
  )
)

(defun ask-logo-placement (/ pt largeur rotation)
  (setq pt (getpoint "\nChoisir le point d'insertion du logo : "))

  (setq largeur (getreal "\nEntrer la largeur / echelle du logo <10> : "))

  (if (null largeur)
    (setq largeur 10.0)
  )

  (setq rotation (getreal "\nEntrer la rotation en degres <0> : "))

  (if (null rotation)
    (setq rotation 0.0)
  )

  (list pt largeur rotation)
)

;; ------------------------------------------------------------------------------------
;; COMMANDE PRINCIPALE : S_LOGO
;; ------------------------------------------------------------------------------------

(defun c:S_LOGO (/ c url imgname filepath item place pt largeur rotation layer)
  (vl-load-com)

  (setq layer "0")

  (initget "A S B U N R G")
  (setq c
    (getkword
      "\nQuel logo voulez-vous ? [Ajouter/Supprimer/Bibliotheque/Url/sNcf/sncfReseau/sncfGare] <B> : "
    )
  )

  (if (null c)
    (setq c "B")
  )

  (cond
    ;; ------------------------------------------------------------
    ;; Ajouter une URL a la bibliotheque
    ;; ------------------------------------------------------------
    ((= c "A")
      (setq url
        (getstring T "\nEntrer l'URL directe de l'image : ")
      )

      (if (or (null url) (= url ""))
        (progn
          (princ "\nErreur : aucune URL indiquee.")
          (exit)
        )
      )

      (if (not (logo-is-url url))
        (progn
          (princ "\nErreur : il faut une URL en http:// ou https://.")
          (exit)
        )
      )

      (setq imgname
        (getstring T "\nNom a donner a l'image dans la bibliotheque <aleatoire> : ")
      )

      (if (= imgname "")
        (setq imgname (random-logo-name))
      )

      (setq filepath (add-logo-url-to-library url imgname))

      (if filepath
        (progn
          (initget "Oui Non")
          (setq c
            (getkword "\nInserer ce logo maintenant ? [Oui/Non] <Oui> : ")
          )

          (if (or (null c) (= c "Oui"))
            (progn
              (setq place (ask-logo-placement))
              (setq pt (nth 0 place))
              (setq largeur (nth 1 place))
              (setq rotation (nth 2 place))

              (insert-logo-from-file filepath pt largeur rotation layer)
            )
          )
        )
      )
    )

    ;; ------------------------------------------------------------
    ;; Supprimer un logo de la bibliotheque
    ;; ------------------------------------------------------------
    ((= c "S")
      (delete-logo-from-library)
    )

    ;; ------------------------------------------------------------
    ;; Utiliser un logo deja enregistre
    ;; ------------------------------------------------------------
    ((= c "B")
      (logo-config-print)

      (setq imgname
        (getstring T "\n\nEntrer le nom exact du logo a inserer : ")
      )

      (setq item (logo-config-get imgname))

      (if (null item)
        (progn
          (princ "\nErreur : ce logo n'existe pas dans la bibliotheque.")
          (exit)
        )
      )

      (setq url (cdr item))

      (setq place (ask-logo-placement))
      (setq pt (nth 0 place))
      (setq largeur (nth 1 place))
      (setq rotation (nth 2 place))

      ;; Re-telecharge toujours depuis l'URL dans le dossier logos du DWG courant
      (insert-logo-from-url url (car item) pt largeur rotation layer)
    )

    ;; ------------------------------------------------------------
    ;; URL manuelle
    ;; ------------------------------------------------------------
    ((= c "U")
      (setq url
        (getstring T "\nEntrer le lien URL direct du logo : ")
      )

      (if (or (null url) (= url ""))
        (progn
          (princ "\nErreur : aucun lien indique.")
          (exit)
        )
      )

      (if (not (logo-is-url url))
        (progn
          (princ "\nErreur : il faut une URL en http:// ou https://.")
          (exit)
        )
      )

      (setq imgname
        (getstring T "\nNom a donner a l'image <aleatoire> : ")
      )

      (if (= imgname "")
        (setq imgname (random-logo-name))
      )

      ;; Enregistre aussi dans logo.config, mais seulement Nom|URL
      (logo-config-add imgname url)

      (setq place (ask-logo-placement))
      (setq pt (nth 0 place))
      (setq largeur (nth 1 place))
      (setq rotation (nth 2 place))

      ;; Re-telecharge dans le dossier du DWG\logos\
      (insert-logo-from-url url imgname pt largeur rotation layer)
    )

    ;; ------------------------------------------------------------
    ;; Logo SNCF
    ;; ------------------------------------------------------------
    ((= c "N")
      (setq url
        "https://upload.wikimedia.org/wikipedia/fr/thumb/f/f7/Logo_SNCF_%282005%29.svg/1280px-Logo_SNCF_%282005%29.svg.png"
      )

      (setq imgname "SNCF")

      ;; Enregistre seulement Nom|URL
      (logo-config-add imgname url)

      (setq place (ask-logo-placement))
      (setq pt (nth 0 place))
      (setq largeur (nth 1 place))
      (setq rotation (nth 2 place))

      (insert-logo-from-url url imgname pt largeur rotation layer)
    )

    ;; ------------------------------------------------------------
    ;; Logo SNCF Reseau
    ;; ------------------------------------------------------------
    ((= c "R")
      (setq url
        "https://upload.wikimedia.org/wikipedia/fr/thumb/e/ec/Logo_SNCF_R%C3%A9seau_2015.svg/3840px-Logo_SNCF_R%C3%A9seau_2015.svg.png"
      )

      (setq imgname "SNCF_RESEAU")

      ;; Enregistre seulement Nom|URL
      (logo-config-add imgname url)

      (setq place (ask-logo-placement))
      (setq pt (nth 0 place))
      (setq largeur (nth 1 place))
      (setq rotation (nth 2 place))

      (insert-logo-from-url url imgname pt largeur rotation layer)
    )

    ;; ------------------------------------------------------------
    ;; Logo SNCF Gares & Connexions
    ;; ------------------------------------------------------------
    ((= c "G")
      (setq url
        "https://upload.wikimedia.org/wikipedia/fr/thumb/a/ae/Logo_SNCF_Gares_%26_Connexions_-_2020.svg/960px-Logo_SNCF_Gares_%26_Connexions_-_2020.svg.png"
      )

      (setq imgname "SNCF_GARES")

      ;; Enregistre seulement Nom|URL
      (logo-config-add imgname url)

      (setq place (ask-logo-placement))
      (setq pt (nth 0 place))
      (setq largeur (nth 1 place))
      (setq rotation (nth 2 place))

      (insert-logo-from-url url imgname pt largeur rotation layer)
    )
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ C_S_PT ------------------------------------------------------------------------------------

(defun pttech:trim (s)
  (if s (vl-string-trim " \t\r\n" s) "")
)

(defun pttech:upper (s)
  (strcase (pttech:trim s))
)

(defun pttech:digitp (s / i ok ch)
  (setq s (pttech:trim s) i 1 ok T)
  (if (= s "") (setq ok nil))
  (while (and ok (<= i (strlen s)))
    (setq ch (substr s i 1))
    (if (not (wcmatch ch "#")) (setq ok nil))
    (setq i (1+ i))
  )
  ok
)

(defun pttech:lenp (s n)
  (= (strlen (pttech:trim s)) n)
)

(defun pttech:valid-digits (s n)
  (and (pttech:digitp s) (pttech:lenp s n))
)

(defun pttech:sanitize-name (s / out i ch)
  (setq s (pttech:trim s) out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (wcmatch ch "[A-Za-z0-9_.-]")
      (setq out (strcat out ch))
      (setq out (strcat out "-"))
    )
    (setq i (1+ i))
  )
  out
)

(defun pttech:region-code (idx)
  (nth idx '("10" "20" "30" "34" "50"))
)

(defun pttech:region-name (idx)
  (nth idx '("PE - Paris-Est" "PN - Paris-Nord" "PSL - Paris-Saint-Lazare" "PRG - Paris-Rive-Gauche" "PSE - Paris-Sud-Est"))
)

(defun pttech:type-name (idx)
  (nth idx '(
    "Pièce spécifique gare/site"
    "Pièce générale Câble/Transmission"
    "Fiche Liaison Spécialisée LS"
    "DOE"
  ))
)

; ------------------------------------------------------------
; Spécialités / familles
; Format : ("Libellé affiché" . "Code")
; ------------------------------------------------------------
(defun pttech:spec-all ()
  '(
    ("18010 - Câble Cuivre" . "18010")
    ("18020 - Fibre Optique" . "18020")
    ("18030 - Réseaux de Câbles Locaux" . "18030")
    ("18110 - RST Analogique" . "18110")
    ("18150 - Radio Locale d'Entreprise" . "18150")
    ("18160 - IRIS" . "18160")
    ("18170 - INPT" . "18170")
    ("18180 - GSMR" . "18180")
    ("18250 - Téléphonie Ferroviaire" . "18250")
    ("18300 - Téléphonie Entreprise" . "18300")
    ("18350 - Atelier d'Energie" . "18350")
    ("18410 - Diagramme Circuits Spéciaux" . "18410")
    ("18420 - Constitution Circuits Spéciaux" . "18420")
    ("18430 - SDH-PDH" . "18430")
    ("18440 - MIC" . "18440")
    ("18450 - Réseau Infranet" . "18450")
    ("18460 - Réseau Infracom" . "18460")
    ("18470 - Réseau RMS" . "18470")
    ("18480 - Fiches de constitution" . "18480")
    ("18510 - Téléaffichage / CATI" . "18510")
    ("18540 - Dauphine" . "18540")
    ("18550 - Infogare / IENA" . "18550")
    ("18610 - Sonorisation" . "18610")
    ("18620 - Télésonorisation" . "18620")
    ("18650 - Chronométrie" . "18650")
    ("18710 - TSV" . "18710")
    ("18720 - GTC" . "18720")
    ("18730 - RETA" . "18730")
    ("18750 - Vidéo (VDS/VDP/VEX)" . "18750")
    ("18810 - Téléopération" . "18810")
    ("18830 - EAS" . "18830")
    ("18840 - STEM" . "18840")
    ("18850 - CADI" . "18850")
    ("18910 - Mur Images" . "18910")
    ("18920 - Interphonie" . "18920")
    ("18930 - CAB" . "18930")
    ("18950 - Réseau Informatique RxD" . "18950")
    ("18960 - PALTT" . "18960")
    ("18970 - DOE" . "18970")
  )
)

; Spécialités autorisées pour le mode "Pièce générale Câble/Transmission"
(defun pttech:spec-cable-trans ()
  '(
    ("18010 - Câble Cuivre" . "18010")
    ("18020 - Fibre Optique" . "18020")
    ("18030 - Réseaux de Câbles Locaux" . "18030")
    ("18410 - Diagramme Circuits Spéciaux" . "18410")
    ("18420 - Constitution Circuits Spéciaux" . "18420")
    ("18430 - SDH-PDH" . "18430")
    ("18440 - MIC" . "18440")
    ("18450 - Réseau Infranet" . "18450")
    ("18460 - Réseau Infracom" . "18460")
  )
)

(defun pttech:spec-list-for-type (type)
  (cond
    ((= type 1) (pttech:spec-cable-trans))
    ((= type 3) '(("18970 - DOE" . "18970")))
    ((= type 2) '(("Non applicable pour LS" . "")))
    (T (pttech:spec-all))
  )
)

; ------------------------------------------------------------
; Sous-familles selon la spécialité
; Format retourné : (("Libellé affiché" . "Code") ...)
; ------------------------------------------------------------
(defun pttech:subfamilies (spec)
  (cond
    ((= spec "18010")
      '(("01 - Diagramme d'utilisation" . "01")
        ("02 - Plan de Pose" . "02")
        ("03 - Notice Technique n°1" . "03")
        ("04 - Notice Technique n°2" . "04")
        ("05 - Plan de Jonction" . "05"))
    )
    ((= spec "18020")
      '(("01 - Diagramme d'utilisation" . "01")
        ("02 - Plan de Pose" . "02")
        ("03 - Notices Techniques" . "03"))
    )
    ((= spec "18030")
      '(("01 - Diagramme d'utilisation" . "01")
        ("02 - Plan de Pose" . "02")
        ("03 - Notices Techniques" . "03"))
    )
    ((= spec "18410")
      '(("01 - Régulation Transport" . "01"))
    )
    ((= spec "18420")
      '(("02 - Régulation Traction" . "02")
        ("03 - Alarme Traction" . "03")
        ("04 - TC-TK Traction" . "04")
        ("05 - Radio Sol Train" . "05")
        ("06 - Maintenance Télécom" . "06")
        ("07 - RETA / Bornes d'appels" . "07")
        ("08 - Télésurveillance" . "08")
        ("09 - Maintenance Traction" . "09")
        ("10 - GSMR" . "10")
        ("11 - Divers" . "11"))
    )
    ((= spec "18430")
      '(("01 - SAGEM" . "01")
        ("02 - Autres" . "02"))
    )
    ((= spec "18440")
      '(("01 - AVARA-NOKIA" . "01")
        ("02 - 2G-3G" . "02")
        ("03 - 4G Alcatel" . "03")
        ("04 - LEGACY" . "04"))
    )
    ((= spec "18450")
      '(("01 - DCO" . "01"))
    )
    ((= spec "18460")
      '(("01 - DCO" . "01"))
    )
    (T
      '(("00 - Non applicable" . "00"))
    )
  )
)

(defun pttech:error (msg)
  (alert (strcat "Erreur : " msg))
)

(defun pttech:fill-popup (key lst)
  (start_list key)
  (mapcar 'add_list lst)
  (end_list)
)

(defun pttech:popup-code (idx lst)
  (cdr (nth idx lst))
)

; ------------------------------------------------------------
; Mise à jour dynamique de l'interface
; ------------------------------------------------------------

(defun pttech:update-spec-list (/ type specs labels)
  (setq type (atoi (get_tile "type")))
  (setq specs (pttech:spec-list-for-type type))
  (setq labels (mapcar 'car specs))

  (pttech:fill-popup "spec" labels)
  (set_tile "spec" "0")
  (setq pttech:*specs-current* specs)

  (pttech:update-sous-list)
)

(defun pttech:update-sous-list (/ type specidx spec subs labels)
  (setq type (atoi (get_tile "type")))

  (if (or (= type 0) (= type 1))
    (progn
      (setq specidx (atoi (get_tile "spec")))
      (setq spec (pttech:popup-code specidx pttech:*specs-current*))
      (setq subs (pttech:subfamilies spec))
    )
    (setq subs '(("00 - Non applicable" . "00")))
  )

  (setq labels (mapcar 'car subs))
  (pttech:fill-popup "sous" labels)
  (set_tile "sous" "0")
  (setq pttech:*subs-current* subs)
)

(defun pttech:mode-lock (/ type)
  (setq type (atoi (get_tile "type")))

  ; 0 enabled / 1 disabled

  ; Champs gare/site : nécessaires seulement en mode 0
  (mode_tile "ligne" (if (= type 0) 0 1))
  (mode_tile "pk"    (if (= type 0) 0 1))
  (mode_tile "tri"   (if (= type 0) 0 1))

  ; Spécialité : utile en mode 0 et 1, forcée/désactivée en LS et DOE
  (mode_tile "spec"  (if (or (= type 0) (= type 1)) 0 1))

  ; Sous-famille : utile seulement en mode 1 Câble/Transmission
  (mode_tile "sous"  (if (= type 1) 0 1))

  ; Ordre : utile en mode 1, LS et DOE
  (mode_tile "ordre" (if (or (= type 1) (= type 2) (= type 3)) 0 1))

  ; Désignation : utile sauf LS
  (mode_tile "desi"  (if (= type 2) 1 0))

  ; Adaptation des valeurs par défaut
  (cond
    ((= type 0)
      (set_tile "ordre" "")
    )
    ((= type 1)
      (if (= (get_tile "ordre") "") (set_tile "ordre" "001"))
    )
    ((= type 2)
      (set_tile "ligne" "")
      (set_tile "pk" "")
      (set_tile "tri" "")
      (set_tile "desi" "")
      (if (/= (strlen (get_tile "ordre")) 5) (set_tile "ordre" "00001"))
    )
    ((= type 3)
      (set_tile "ligne" "")
      (set_tile "pk" "")
      (set_tile "tri" "")
      (if (= (get_tile "ordre") "") (set_tile "ordre" "001"))
    )
  )

  (pttech:update-spec-list)
)

; ------------------------------------------------------------
; Génération de référence
; ------------------------------------------------------------

(defun pttech:make-reference (type reg ligne pk tri spec sous ordre desi / ref)
  (setq reg   (pttech:region-code reg))
  (setq ligne (pttech:trim ligne))
  (setq pk    (pttech:trim pk))
  (setq tri   (pttech:upper tri))
  (setq spec  (pttech:trim spec))
  (setq sous  (pttech:trim sous))
  (setq ordre (pttech:trim ordre))
  (setq desi  (pttech:sanitize-name desi))

  (cond
    ; 0 = Pièce spécifique gare/site :
    ; REGION_LIGNE_PK_TRIGRAMME_SPECIALITE_DESIGNATION
    ((= type 0)
      (cond
        ((not (pttech:valid-digits ligne 3)) (pttech:error "la ligne doit contenir 3 chiffres.") nil)
        ((not (pttech:valid-digits pk 3))    (pttech:error "le PK doit contenir 3 chiffres.") nil)
        ((or (< (strlen tri) 1) (> (strlen tri) 3)) (pttech:error "le trigramme doit contenir entre 1 et 3 caractères.") nil)
        ((not (pttech:valid-digits spec 5))  (pttech:error "la spécialité doit contenir 5 chiffres.") nil)
        ((or (= desi "") (> (strlen desi) 16)) (pttech:error "la désignation est obligatoire et limitée à 16 caractères.") nil)
        (T (strcat reg "_" ligne "_" pk "_" tri "_" spec "_" desi))
      )
    )

    ; 1 = Pièce générale Câble / Transmission :
    ; REGION_SPECIALITE_SOUSFAMILLE_ORDRE_DESIGNATION
    ((= type 1)
      (cond
        ((not (pttech:valid-digits spec 5))  (pttech:error "la spécialité doit contenir 5 chiffres.") nil)
        ((not (pttech:valid-digits sous 2))  (pttech:error "la sous-famille doit contenir 2 chiffres.") nil)
        ((not (pttech:valid-digits ordre 3)) (pttech:error "le numéro d'ordre doit contenir 3 chiffres.") nil)
        ((= desi "")                         (pttech:error "la désignation/type de document est obligatoire.") nil)
        (T (strcat reg "_" spec "_" sous "_" ordre "_" desi))
      )
    )

    ; 2 = Liaison spécialisée :
    ; LS_REGION_ORDRE5
    ((= type 2)
      (cond
        ((not (pttech:valid-digits ordre 5)) (pttech:error "pour une LS, le numéro d'ordre doit contenir 5 chiffres.") nil)
        (T (strcat "LS_" reg "_" ordre))
      )
    )

    ; 3 = DOE :
    ; REGION_18970_ORDRE_DESIGNATION
    ((= type 3)
      (cond
        ((not (pttech:valid-digits ordre 3)) (pttech:error "le numéro d'ordre doit contenir 3 chiffres.") nil)
        ((or (= desi "") (> (strlen desi) 16)) (pttech:error "la désignation DOE est obligatoire et limitée à 16 caractères.") nil)
        (T (strcat reg "_18970_" ordre "_" desi))
      )
    )
  )
)

(defun pttech:dcl-path (/ p f)
  (setq p (vl-filename-mktemp "pttech.dcl"))
  (setq f (open p "w"))
  (write-line
"pttech : dialog {
  label = \"Générateur pièce technique DE.TL.IDF\";

  : boxed_column {
    label = \"Mode de référencement\";
    : popup_list { key = \"type\"; label = \"Type\"; width = 60; }
  }

  : boxed_column {
    label = \"Champs utilisés selon le mode choisi\";
    : popup_list { key = \"region\"; label = \"Région\"; width = 60; }
    : edit_box { key = \"ligne\"; label = \"Ligne - 3 chiffres\"; edit_width = 20; value = \"\"; }
    : edit_box { key = \"pk\"; label = \"PK - 3 chiffres\"; edit_width = 20; value = \"\"; }
    : edit_box { key = \"tri\"; label = \"Site / gare - 1 à 3 caractères\"; edit_width = 20; value = \"\"; }
    : popup_list { key = \"spec\"; label = \"Spécialité / famille\"; width = 60; }
    : popup_list { key = \"sous\"; label = \"Sous-famille\"; width = 60; }
    : edit_box { key = \"ordre\"; label = \"N° ordre - 3 chiffres, ou 5 pour LS\"; edit_width = 20; value = \"\"; }
    : edit_box { key = \"desi\"; label = \"Désignation\"; edit_width = 32; value = \"\"; }
  }

  : boxed_column {
    label = \"Sortie dans le dessin\";
    : edit_box { key = \"ht\"; label = \"Hauteur texte\"; edit_width = 12; value = \"2.5\"; }
    : toggle { key = \"cartouche\"; label = \"Créer un texte multi-lignes avec détails\"; value = \"1\"; }
  }

  spacer;
  ok_cancel;
}" f)
  (close f)
  p
)

(defun pttech:dialog (/ dcl dcl_id ret type region ligne pk tri specidx sousidx spec sous ordre desi ht cartouche ref)
  (setq dcl (pttech:dcl-path))
  (setq dcl_id (load_dialog dcl))

  (if (not (new_dialog "pttech" dcl_id))
    (progn
      (unload_dialog dcl_id)
      (vl-file-delete dcl)
      nil
    )
    (progn
      (pttech:fill-popup "type" '(
        "Pièce spécifique à une gare / site"
        "Pièce générale Câble / Transmission"
        "Fiche Liaison Spécialisée - LS"
        "DOE"
      ))
      (pttech:fill-popup "region" '(
        "10 - PE - Paris-Est"
        "20 - PN - Paris-Nord"
        "30 - PSL - Paris-Saint-Lazare"
        "34 - PRG - Paris-Rive-Gauche"
        "50 - PSE - Paris-Sud-Est"
      ))

      (set_tile "type" "0")
      (set_tile "region" "0")

      (setq pttech:*specs-current* (pttech:spec-list-for-type 0))
      (pttech:fill-popup "spec" (mapcar 'car pttech:*specs-current*))
      (set_tile "spec" "8") ; 18250 Téléphonie Ferroviaire par défaut

      (pttech:update-sous-list)
      (pttech:mode-lock)

      (action_tile "type" "(pttech:mode-lock)")
      (action_tile "spec" "(pttech:update-sous-list)")

      (action_tile "accept"
        "(setq type (atoi (get_tile \"type\"))
               region (atoi (get_tile \"region\"))
               ligne (get_tile \"ligne\")
               pk (get_tile \"pk\")
               tri (get_tile \"tri\")
               specidx (atoi (get_tile \"spec\"))
               sousidx (atoi (get_tile \"sous\"))
               spec (pttech:popup-code specidx pttech:*specs-current*)
               sous (pttech:popup-code sousidx pttech:*subs-current*)
               ordre (get_tile \"ordre\")
               desi (get_tile \"desi\")
               ht (atof (get_tile \"ht\"))
               cartouche (= (get_tile \"cartouche\") \"1\"))
         (done_dialog 1))"
      )

      (action_tile "cancel" "(done_dialog 0)")
      (setq ret (start_dialog))

      (unload_dialog dcl_id)
      (vl-file-delete dcl)

      (if (= ret 1)
        (progn
          (setq ref (pttech:make-reference type region ligne pk tri spec sous ordre desi))
          (if ref
            (list ref type region ligne pk tri spec sous ordre desi ht cartouche)
            nil
          )
        )
        nil
      )
    )
  )
)

(defun pttech:insert-mtext (pt ht txt)
  (entmakex
    (list
      '(0 . "MTEXT")
      '(100 . "AcDbEntity")
      (cons 8 (getvar "CLAYER"))
      '(100 . "AcDbMText")
      (cons 10 pt)
      (cons 40 ht)
      (cons 41 180.0)
      (cons 71 1)
      (cons 7 (getvar "TEXTSTYLE"))
      (cons 1 txt)
    )
  )
)

(defun c:S_PT (/ data ref type region ligne pk tri spec sous ordre desi ht cartouche pt txt)
  (setq data (pttech:dialog))
  (if data
    (progn
      (setq ref       (nth 0 data)
            type      (nth 1 data)
            region    (nth 2 data)
            ligne     (nth 3 data)
            pk        (nth 4 data)
            tri       (nth 5 data)
            spec      (nth 6 data)
            sous      (nth 7 data)
            ordre     (nth 8 data)
            desi      (nth 9 data)
            ht        (nth 10 data)
            cartouche (nth 11 data)
      )

      (setq pt (getpoint "\nPoint d'insertion du texte : "))

      (if pt
        (progn
          (setq txt ref)

          (pttech:insert-mtext pt ht txt)
          (princ (strcat "\nRéférence générée : " ref))
        )
      )
    )
  )
  (princ)
)

;; ------------------------------------------------------------------------------------ C_S_QUAI / C_S_EQP_QUAI ------------------------------------------------------------------------------------

(defun draw-pancarte (pt t2 ds layer / x y c texte_pancarte)
  (setq x (car pt))
  (setq y (cadr pt))

  (initget "D G")
  (setq c (getkword "\nL'orientation de la pancarte ? [Droite/Gauche] <D> : "))

  ;; Valeur par défaut : Droite
  (if (null c)
    (setq c "D")
  )

  (if (= c "D")
    (progn
        (setq texte_pancarte
        (getstring T "\nEntrer le texte de la pancarte  (\\ pour sauter une ligne) : "))

        (if (= texte_pancarte "")
          (setq texte_pancarte "-")
        )

        (draw-line (list (+ x t2 ds) y 0) (list (+ x t2 ds) (+ y 8) 0) layer "Continuous" 1)
        (draw-rect (list (+ x t2 ds) (+ y 8) 0) (list (+ x t2 ds 8) (+ y 8 8) 0) layer)
        (draw-mtext (list (+ x t2 ds 4) (+ y 12) 0) texte_pancarte layer 2 0 20)
    )
    (progn
        (setq texte_pancarte
        (getstring T "\nEntrer le texte de la pancarte : "))

        (if (= texte_pancarte "")
          (setq texte_pancarte "-")
        )

        (draw-line (list (+ x t2 ds) y 0) (list (+ x t2 ds) (+ y 8) 0) layer "Continuous" 1)
        (draw-rect (list (+ x t2 ds) (+ y 8) 0) (list (- (+ x t2 ds) 8) (+ y 8 8) 0) layer)
        (draw-mtext (list (- (+ x t2 ds) 4) (+ y 12) 0) texte_pancarte layer 2 0 20)
    )
  )

  (draw-mtext (list (+ x t2 ds) (+ y 18) 0)  (strcat (rtos ds 2 2) "m") layer 2 0 20)
)

(defun draw-catenaire (pt t2 ds layer / x y c numero_cat)
  (setq x (car pt))
  (setq y (cadr pt))

  (initget "D G")
  (setq c (getkword "\nL'orientation de la catenaire ? [Droite/Gauche] <D> : "))

  ;; Valeur par défaut : Droite
  (if (null c)
    (setq c "D")
  )

  (if (= c "D")
    (progn
        (draw-line (list (- (+ x t2 ds) 0.15) y 0) (list (- (+ x t2 ds) 0.15) (+ y 30) 0) layer "Continuous" 1)
        (draw-line (list (+ x t2 ds 0.15) y 0) (list (+ x t2 ds 0.15) (+ y 30) 0) layer "Continuous" 1)

        (draw-line (list (- (+ x t2 ds) 0.15) (+ y 30) 0) (list (+ x t2 ds 0.75) (+ y 30) 0) layer "Continuous" 1)
        (draw-line (list (+ x t2 ds 0.75) (+ y 30) 0) (list (+ x t2 ds 0.75 3.15) (+ y 27.23) 0) layer "Continuous" 1)
        (draw-line (list (+ x t2 ds 0.75 3.15) (+ y 27.23) 0) (list (- (+ x t2 ds 0.75 3.15) 3.75) (+ y 27.23) 0) layer "Continuous" 1)

        (draw-line (list (+ x t2 ds 0.75 3.15) (+ y 27.23) 0) (list (+ x t2 ds 0.75 3.15 5.40) (- (+ y 27.23) 2.65) 0) layer "Continuous" 1)
        (draw-line (list (+ x t2 ds 0.75 3.15 5.40) (- (+ y 27.23) 2.65) 0) (list (- (+ x t2 ds 0.75 3.15 5.40) 9.15) (- (+ y 27.23) 2.65) 0) layer "Continuous" 1)

    )
    (progn
        (draw-line (list (- (+ x t2 ds) 0.15) y 0) (list (- (+ x t2 ds) 0.15) (+ y 30) 0) layer "Continuous" 1)
        (draw-line (list (+ x t2 ds 0.15) y 0) (list (+ x t2 ds 0.15) (+ y 30) 0) layer "Continuous" 1)

        (draw-line (list (+ x t2 ds 0.15) (+ y 30) 0) (list (- (+ x t2 ds 0.15) 0.90) (+ y 30) 0) layer "Continuous" 1)
        (draw-line (list (- (+ x t2 ds 0.15) 0.90) (+ y 30) 0) (list (- (+ x t2 ds) 0.75 3.15) (+ y 27.23) 0) layer "Continuous" 1)
        (draw-line (list (- (+ x t2 ds) 0.75 3.15) (+ y 27.23) 0) (list (- (+ x t2 ds 3.75) 0.75 3.15) (+ y 27.23) 0) layer "Continuous" 1)

        (draw-line (list (- (+ x t2 ds) 0.75 3.15) (+ y 27.23) 0) (list (- (+ x t2 ds) 0.75 3.15 5.40) (- (+ y 27.23) 2.65) 0) layer "Continuous" 1)
        (draw-line (list (- (+ x t2 ds) 0.75 3.15 5.40) (- (+ y 27.23) 2.65) 0) (list (- (+ x t2 ds 9.15) 0.75 3.15 5.40) (- (+ y 27.23) 2.65) 0) layer "Continuous" 1)
    )
  )

  (setq numero_cat
  (getstring T "\nEntrer le numéro de la catenaire (ex. 88 / 09) : "))  
  (if (= numero_cat "")
    (setq numero_cat "? / ?")
  )

  (draw-mtext (list (+ x t2 ds) (+ y 37) 0)  (strcat "cat\\" numero_cat "\\" (rtos ds 2 2) "m") layer 2 0 20)
)

(defun draw-camera (pt t2 ds layer / x y numero_cam)
  (setq x (car pt))
  (setq y (cadr pt))

  (initget "D G GD DG BD BG")
  (setq c (getkword "\nL'orientation de la caméra ou des cameras ? [Droite/Gauche/(GD)Gauche-Droite/(DG)Droite-Gauche/(BD)Bas-Droite/(BG)Bas-Gauche] <D> : "))

  ;; Valeur par défaut : Droite
  (if (null c)
    (setq c "D")
  )

  (initget "E P R D")
  (setq s (getkword "\nLe statut de la caméra ou des caméras ? [Existant/Pose/Repose/Depose] <E> : "))

  (if (null s)
    (setq s "E")
  )

  (cond
    ((= s "E")
      (setq layer "TL_MATERIEL_EXISTANT")
    )

    ((= s "P")
      (setq layer "TL_MATERIEL_POSE")
    )

    ((= s "R")
      (setq layer "TL_MATERIEL_REPOSE")
    )

    ((= s "D")
      (setq layer "TL_MATERIEL_DEPOSE")
    )
  )

  (cond
  ;; DROITE
  ((= c "D")
    (progn
      (draw-line (list (+ x t2 ds) y 0) (list (+ x t2 ds) (+ y 15) 0) layer "Continuous" 1)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50) (+ y 15 3) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 0.19) 0) (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) layer)

      (draw-line (list (- (+ x t2 ds 3.50) 0.88) (+ y 15 3) 0) (list (- (+ x t2 ds 3.50) 0.88) (- (+ y 15 3) 3) 0)layer "Continuous" 1)

      (draw-line (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) (list (+ x t2 ds 3.50 0.35) (- (+ y 15 3) 0.19 0.35) 0)layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50 0.35) (- (+ y 15 3) 0.19 0.35) 0) (list (+ x t2 ds 3.50 0.35 2.72) (- (+ y 15 3 1.27) 0.19 0.35) 0) layer "Continuous" 1)

      (draw-line (list (+ x t2 ds 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50 0.35) (+ y 15 0.35) 0)layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50 0.35) (+ y 15 0.35) 0) (list (+ x t2 ds 3.50 0.35 2.72) (- (+ y 15 0.35) 1.27) 0)layer "Continuous" 1)

      (setq numero_cam (getstring T "\nEntrer le numéro de la camera (ex. C1) : "))  
      (if (= numero_cam "")
        (setq numero_cam "?")
      )

      (draw-mtext (list (+ x t2 ds) (+ y 25) 0)  (strcat numero_cam "\\" (rtos ds 2 2) "m") layer 2 0 20)

      (hatch-poly4-color (list (+ x t2 ds) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds 63.5) 50) (- y 2 2.6) 0) layer 231) 
      (draw-poly4 (list (+ x t2 ds) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds 63.5) 50) (- y 2 2.6) 0) layer) 

      (draw-mtext (list (+ x t2 ds 32.5) (- y 2 1.3) 0) numero_cam layer 2 0 20)
    )
  )

  ;; GAUCHE
  ((= c "G")
    (progn
      (draw-line (list (+ x t2 ds) y 0) (list (+ x t2 ds) (+ y 15) 0) layer "Continuous" 1)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50) (+ y 15 3) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 0.19) 0) (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) layer)

      (draw-line (list (- (+ x t2 ds 0.88) 3.5) (+ y 15) 0) (list (- (+ x t2 ds 0.88) 3.5) (+ y 15 3) 0) layer "Continuous" 1)

      (draw-line (list (- (+ x t2 ds) 3.5) (+ y 15 3) 0) (list (- (+ x t2 ds) 3.5 0.35) (- (+ y 15 3) 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.5 0.35) (- (+ y 15 3) 0.35) 0) (list (- (+ x t2 ds) 3.5 0.35 2.72) (- (+ y 15 3 1.27) 0.35) 0) layer "Continuous" 1)

      (draw-line (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (- (+ x t2 ds) 3.50 0.35) (+ y 15 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.50 0.35) (+ y 15 0.35) 0) (list (- (+ x t2 ds) 3.50 0.35 2.72) (- (+ y 15 0.35) 1.27) 0) layer "Continuous" 1)
      
      (setq numero_cam (getstring T "\nEntrer le numéro de la camera (ex. C1) : "))  
      (if (= numero_cam "")
        (setq numero_cam "?")
      )

      (draw-mtext (list (+ x t2 ds) (+ y 25) 0)  (strcat numero_cam "\\" (rtos ds 2 2) "m") layer 2 0 20)

      (hatch-poly4-color (list (+ x t2 ds) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6 2.6) 0) (list (- (+ x t2 ds 50) 63.5) (- y 2 2.6 2.6) 0) layer 231) 
      (draw-poly4 (list (+ x t2 ds) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6 2.6) 0) (list (- (+ x t2 ds 50) 63.5) (- y 2 2.6 2.6) 0) layer) 

      (draw-mtext (list (- (+ x t2 ds) 32.5) (- y 2 1.3 2.6) 0) numero_cam layer 2 0 20)
    )
  )

  ;; GAUCHE/DROITE
  ((= c "GD")
    (progn
      (draw-line (list (+ x t2 ds) y 0) (list (+ x t2 ds) (+ y 15) 0) layer "Continuous" 1)

      ;;GAUCHE
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50) (+ y 15 3) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 0.19) 0) (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) layer)
      (draw-line (list (- (+ x t2 ds 0.88) 3.5) (+ y 15) 0) (list (- (+ x t2 ds 0.88) 3.5) (+ y 15 3) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.5) (+ y 15 3) 0) (list (- (+ x t2 ds) 3.5 0.35) (- (+ y 15 3) 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.5 0.35) (- (+ y 15 3) 0.35) 0) (list (- (+ x t2 ds) 3.5 0.35 2.72) (- (+ y 15 3 1.27) 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (- (+ x t2 ds) 3.50 0.35) (+ y 15 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.50 0.35) (+ y 15 0.35) 0) (list (- (+ x t2 ds) 3.50 0.35 2.72) (- (+ y 15 0.35) 1.27) 0) layer "Continuous" 1)

      ;; DROITE
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 3) 0) (list (+ x t2 ds 3.50) (+ y 15 3 3) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 0.19 3) 0) (list (+ x t2 ds 3.50) (- (+ y 15 3 3) 0.19) 0) layer)
      (draw-line (list (- (+ x t2 ds 3.50) 0.88) (+ y 15 3 3) 0) (list (- (+ x t2 ds 3.50) 0.88) (- (+ y 15 3 3) 3) 0) layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50) (- (+ y 15 3 3) 0.19) 0) (list (+ x t2 ds 3.50 0.35) (- (+ y 15 3 3) 0.19 0.35) 0) layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50 0.35) (- (+ y 15 3 3) 0.19 0.35) 0) (list (+ x t2 ds 3.50 0.35 2.72) (- (+ y 15 3 1.27 3) 0.19 0.35) 0) layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50) (+ y 15 3) 0) (list (+ x t2 ds 3.50 0.35) (+ y 15 0.35 3) 0)layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50 0.35) (+ y 15 0.35 3) 0) (list (+ x t2 ds 3.50 0.35 2.72) (- (+ y 15 0.35 3) 1.27) 0)layer "Continuous" 1)

      (setq numero_cam (getstring T "\nEntrer le numéro des cameras (ex. C1 - C2) : "))  
      (if (= numero_cam "")
        (setq numero_cam "?")
      )

      (draw-mtext (list (+ x t2 ds) (+ y 28) 0)  (strcat numero_cam "\\" (rtos ds 2 2) "m") layer 2 0 20)

      (hatch-poly4-color (list (+ x t2 ds) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds 63.5) 50) (- y 2 2.6) 0) layer 231) 
      (draw-poly4 (list (+ x t2 ds) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds 63.5) 50) (- y 2 2.6) 0) layer) 

      (draw-mtext (list (+ x t2 ds 32.5) (- y 2 1.3) 0) "?" layer 2 0 20)

      (hatch-poly4-color (list (+ x t2 ds) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6 2.6) 0) (list (- (+ x t2 ds 50) 63.5) (- y 2 2.6 2.6) 0) layer 231) 
      (draw-poly4 (list (+ x t2 ds) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6 2.6) 0) (list (- (+ x t2 ds 50) 63.5) (- y 2 2.6 2.6) 0) layer) 

      (draw-mtext (list (- (+ x t2 ds) 32.5) (- y 2 1.3 2.6) 0) "?" layer 2 0 20)
    )
  )

  ;; DROITE/GAUCHE
  ((= c "DG")
    (progn
      (draw-line (list (+ x t2 ds) y 0) (list (+ x t2 ds) (+ y 15) 0) layer "Continuous" 1)

      ;; DROITE
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50) (+ y 15 3) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 0.19) 0) (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) layer)
      (draw-line (list (- (+ x t2 ds 3.50) 0.88) (+ y 15 3) 0) (list (- (+ x t2 ds 3.50) 0.88) (- (+ y 15 3) 3) 0) layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) (list (+ x t2 ds 3.50 0.35) (- (+ y 15 3) 0.19 0.35) 0) layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50 0.35) (- (+ y 15 3) 0.19 0.35) 0) (list (+ x t2 ds 3.50 0.35 2.72) (- (+ y 15 3 1.27) 0.19 0.35) 0) layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50 0.35) (+ y 15 0.35) 0) layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50 0.35) (+ y 15 0.35) 0) (list (+ x t2 ds 3.50 0.35 2.72) (- (+ y 15 0.35) 1.27) 0) layer "Continuous" 1)

      ;;GAUCHE
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 3) 0) (list (+ x t2 ds 3.50) (+ y 15 3 3) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 0.19 3) 0) (list (+ x t2 ds 3.50) (- (+ y 15 3 3) 0.19) 0) layer)
      (draw-line (list (- (+ x t2 ds 0.88) 3.5) (+ y 15 3) 0) (list (- (+ x t2 ds 0.88) 3.5) (+ y 15 3 3) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.5) (+ y 15 3 3) 0) (list (- (+ x t2 ds) 3.5 0.35) (- (+ y 15 3 3) 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.5 0.35) (- (+ y 15 3 3) 0.35) 0) (list (- (+ x t2 ds) 3.5 0.35 2.72) (- (+ y 15 3 1.27 3) 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.50) (+ y 15 3) 0) (list (- (+ x t2 ds) 3.50 0.35) (+ y 15 0.35 3) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.50 0.35) (+ y 15 0.35 3) 0) (list (- (+ x t2 ds) 3.50 0.35 2.72) (- (+ y 15 0.35 3) 1.27) 0) layer "Continuous" 1)

      (setq numero_cam (getstring T "\nEntrer le numéro des cameras (ex. C1 - C2) : "))  
      (if (= numero_cam "")
        (setq numero_cam "?")
      )

      (draw-mtext (list (+ x t2 ds) (+ y 28) 0)  (strcat numero_cam "\\" (rtos ds 2 2) "m") layer 2 0 20)

      (hatch-poly4-color (list (+ x t2 ds) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds 63.5) 50) (- y 2 2.6) 0) layer 231) 
      (draw-poly4 (list (+ x t2 ds) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds 63.5) 50) (- y 2 2.6) 0) layer) 

      (draw-mtext (list (+ x t2 ds 32.5) (- y 2 1.3) 0) "C?" layer 2 0 20)

      (hatch-poly4-color (list (+ x t2 ds) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6 2.6) 0) (list (- (+ x t2 ds 50) 63.5) (- y 2 2.6 2.6) 0) layer 231) 
      (draw-poly4 (list (+ x t2 ds) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6 2.6) 0) (list (- (+ x t2 ds 50) 63.5) (- y 2 2.6 2.6) 0) layer) 

      (draw-mtext (list (- (+ x t2 ds) 32.5) (- y 2 1.3 2.6) 0) "C?" layer 2 0 20)
    )
  )

  ((= c "BD")
    (progn
      (draw-line (list (+ x t2 ds) (+ y 15) 0) (list (+ x t2 ds) (+ y 15 7.5) 0) layer "Continuous" 1)

      (draw-rect (list (- (+ x t2 ds) 5) (+ y 15 7.5) 0) (list (+ x t2 ds 5) (+ y 15 7.5 1) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50) (+ y 15 3) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 0.19) 0) (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) layer)
      (draw-line (list (- (+ x t2 ds 3.50) 0.88) (+ y 15 3) 0) (list (- (+ x t2 ds 3.50) 0.88) (- (+ y 15 3) 3) 0)layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) (list (+ x t2 ds 3.50 0.35) (- (+ y 15 3) 0.19 0.35) 0)layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50 0.35) (- (+ y 15 3) 0.19 0.35) 0) (list (+ x t2 ds 3.50 0.35 2.72) (- (+ y 15 3 1.27) 0.19 0.35) 0) layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50 0.35) (+ y 15 0.35) 0)layer "Continuous" 1)
      (draw-line (list (+ x t2 ds 3.50 0.35) (+ y 15 0.35) 0) (list (+ x t2 ds 3.50 0.35 2.72) (- (+ y 15 0.35) 1.27) 0)layer "Continuous" 1)

      (setq numero_cam (getstring T "\nEntrer le numéro de la camera (ex. C1) : "))  
      (if (= numero_cam "")
        (setq numero_cam "?")
      )

      (draw-mtext (list (+ x t2 ds) (+ y 25 3) 0)  (strcat numero_cam "\\" (rtos ds 2 2) "m") layer 2 0 20)
      (hatch-poly4-color (list (+ x t2 ds) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds 63.5) 50) (- y 2 2.6) 0) layer 231) 
      (draw-poly4 (list (+ x t2 ds) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2) 0) (list (+ x t2 ds 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds 63.5) 50) (- y 2 2.6) 0) layer) 
      (draw-mtext (list (+ x t2 ds 32.5) (- y 2 1.3) 0) numero_cam layer 2 0 20)

      (hatch-poly4-pattern (list (- (+ x t2 ds) 5) (+ y 15 7.5) 0) (list (+ x t2 ds 5) (+ y 15 7.5) 0) (list (+ x t2 ds 5) (+ y 15 7.5 1) 0) (list (- (+ x t2 ds 5) 10) (+ y 15 7.5 1) 0)  layer 7 "ANSI31" 0.25)
    )
  )

  ((= c "BG")
    (progn
      (draw-line (list (+ x t2 ds) (+ y 15) 0) (list (+ x t2 ds) (+ y 15 7.5) 0) layer "Continuous" 1)

      (draw-rect (list (- (+ x t2 ds) 5) (+ y 15 7.5) 0) (list (+ x t2 ds 5) (+ y 15 7.5 1) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (+ x t2 ds 3.50) (+ y 15 3) 0) layer)
      (draw-rect (list (- (+ x t2 ds) 3.50) (+ y 15 0.19) 0) (list (+ x t2 ds 3.50) (- (+ y 15 3) 0.19) 0) layer)

      (draw-line (list (- (+ x t2 ds 0.88) 3.5) (+ y 15) 0) (list (- (+ x t2 ds 0.88) 3.5) (+ y 15 3) 0) layer "Continuous" 1)

      (draw-line (list (- (+ x t2 ds) 3.5) (+ y 15 3) 0) (list (- (+ x t2 ds) 3.5 0.35) (- (+ y 15 3) 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.5 0.35) (- (+ y 15 3) 0.35) 0) (list (- (+ x t2 ds) 3.5 0.35 2.72) (- (+ y 15 3 1.27) 0.35) 0) layer "Continuous" 1)

      (draw-line (list (- (+ x t2 ds) 3.50) (+ y 15) 0) (list (- (+ x t2 ds) 3.50 0.35) (+ y 15 0.35) 0) layer "Continuous" 1)
      (draw-line (list (- (+ x t2 ds) 3.50 0.35) (+ y 15 0.35) 0) (list (- (+ x t2 ds) 3.50 0.35 2.72) (- (+ y 15 0.35) 1.27) 0) layer "Continuous" 1)
      
      (setq numero_cam (getstring T "\nEntrer le numéro de la camera (ex. C1) : "))  
      (if (= numero_cam "")
        (setq numero_cam "?")
      )

      (draw-mtext (list (+ x t2 ds) (+ y 25 3) 0)  (strcat numero_cam "\\" (rtos ds 2 2) "m") layer 2 0 20)
      (hatch-poly4-color (list (+ x t2 ds) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6 2.6) 0) (list (- (+ x t2 ds 50) 63.5) (- y 2 2.6 2.6) 0) layer 231) 
      (draw-poly4 (list (+ x t2 ds) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6) 0) (list (- (+ x t2 ds) 63.5) (- y 2 2.6 2.6) 0) (list (- (+ x t2 ds 50) 63.5) (- y 2 2.6 2.6) 0) layer) 
      (draw-mtext (list (- (+ x t2 ds) 32.5) (- y 2 1.3 2.6) 0) numero_cam layer 2 0 20)

      (hatch-poly4-pattern (list (- (+ x t2 ds) 5) (+ y 15 7.5) 0) (list (+ x t2 ds 5) (+ y 15 7.5) 0) (list (+ x t2 ds 5) (+ y 15 7.5 1) 0) (list (- (+ x t2 ds 5) 10) (+ y 15 7.5 1) 0)  layer 7 "ANSI31" 0.25)
    )
  )
  )
)

(defun draw-antenne (pt t2 ds layer / x y c s nom_ant taille_antenne)
  (setq x (car pt))
  (setq y (cadr pt))

  (initget "D G")
  (setq c (getkword "\nL'orientation de l'antenne ? [Droite/Gauche] <D> : "))

  ;; Valeur par défaut : Droite
  (if (null c)
    (setq c "D")
  )

  (initget "E P R D")
  (setq s (getkword "\nLe statut de l'antenne ? [Existant/Pose/Repose/Depose] <E> : "))

  (if (null s)
    (setq s "E")
  )

  (cond
    ((= s "E")
      (setq layer "TL_MATERIEL_EXISTANT")
    )

    ((= s "P")
      (setq layer "TL_MATERIEL_POSE")
    )

    ((= s "R")
      (setq layer "TL_MATERIEL_REPOSE")
    )

    ((= s "D")
      (setq layer "TL_MATERIEL_DEPOSE")
    )
  )

  (initget "31 61 91")
  (setq taille_antenne
    (getkword "\nTaille de l'antenne ? [31/61/91] <31> : ")
  )

  ;; Valeur par défaut : 31 m
  (if (null taille_antenne)
    (setq taille_antenne "31")
  )

  (setq nom_ant (getstring T "\nEntrer le nom de l'antenne (ex. A1) : "))  
    (if (= nom_ant "")
      (setq nom_ant "?")
    )

  (if (= c "D")
    (progn
        (cond
          ((= taille_antenne "31")
              (draw-rect (list (+ x t2 ds) (- y 25) 0) (list (+ x t2 ds 1.5) (- y 25 0.70) 0) layer)
              (draw-mtext (list (+ x t2 ds 0.75) (- y 28) 0) (strcat (rtos ds 2 2) "m") layer 2 0 10)

              (draw-line (list (+ x t2 ds) (- y 25) 0) (list (+ x t2 ds 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38) (- y 25) 0) (list (+ x t2 ds 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38) (- y 25) 0) (list (+ x t2 ds 0.38 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38 0.38) (- y 25) 0) (list (+ x t2 ds 1.5) (- y 25 0.70) 0) layer "Continuous" 1)

              (draw-line (list (+ x t2 ds) (- y 25 0.70) 0) (list (+ x t2 ds 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 0.38 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 1.5) (- y 25) 0) layer "Continuous" 1)

              ;;31M
              (draw-line (list (+ x t2 ds 1.5) (- y 25 0.35) 0) (list (+ x t2 ds 1.5 24) (- y 25 0.35) 0) layer "Continuous" 1)
              (draw-line-color (list (+ x t2 ds 1.5 24) (- y 25 0.35) 0) (list (+ x t2 ds 1.5 24 7) (- y 25 0.35) 0) layer "Continuous" 1 130)
              (draw-mtext (list (+ x t2 ds 1.5 15.5) (- y 22) 0) nom_ant layer 2 0 10)

              (draw-rect (list (+ x t2 ds 1.5 24 7) (- y 25) 0) (list (+ x t2 ds 1.5 24 7 1.50) (- y 25 0.70) 0) layer)
              (draw-mtext (list (+ x t2 ds 0.75 32.5) (- y 28) 0) (strcat (rtos (+ ds 31) 2 2) "m") layer 2 0 10)

              (draw-line (list (+ x t2 ds 1.5 24 7 1.50) (+ (- y 25 0.70) 0.35) 0) (list (+ x t2 ds 1.5 24 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 1.5 24 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) (list (+ x t2 ds 1.5 24 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 1.5 24 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) (list (+ x t2 ds 1.5 24 7 1.50 1.25 1.62 2.49) (+ (- y 25 0.70 1.73) 0.35 1.16 2.32) 0) layer "Continuous" 1)
          )
          ((= taille_antenne "61")
              (draw-rect (list (+ x t2 ds) (- y 25) 0) (list (+ x t2 ds 1.5) (- y 25 0.70) 0) layer)
              (draw-mtext (list (+ x t2 ds 0.75) (- y 28) 0) (strcat (rtos ds 2 2) "m") layer 2 0 10)

              (draw-line (list (+ x t2 ds) (- y 25) 0) (list (+ x t2 ds 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38) (- y 25) 0) (list (+ x t2 ds 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38) (- y 25) 0) (list (+ x t2 ds 0.38 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38 0.38) (- y 25) 0) (list (+ x t2 ds 1.5) (- y 25 0.70) 0) layer "Continuous" 1)

              (draw-line (list (+ x t2 ds) (- y 25 0.70) 0) (list (+ x t2 ds 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 0.38 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 1.5) (- y 25) 0) layer "Continuous" 1)

              ;;61M
              (draw-line (list (+ x t2 ds 1.5) (- y 25 0.35) 0) (list (+ x t2 ds 1.5 54) (- y 25 0.35) 0) layer "Continuous" 1)
              (draw-line-color (list (+ x t2 ds 1.5 54) (- y 25 0.35) 0) (list (+ x t2 ds 1.5 54 7) (- y 25 0.35) 0) layer "Continuous" 1 130)
              (draw-mtext (list (+ x t2 ds 1.5 30.5) (- y 22) 0) nom_ant layer 2 0 10)

              (draw-rect (list (+ x t2 ds 1.5 54 7) (- y 25) 0) (list (+ x t2 ds 1.5 54 7 1.50) (- y 25 0.70) 0) layer)
              (draw-mtext (list (+ x t2 ds 0.75 62.5) (- y 28) 0) (strcat (rtos (+ ds 61) 2 2) "m") layer 2 0 10)

              (draw-line (list (+ x t2 ds 1.5 54 7 1.50) (+ (- y 25 0.70) 0.35) 0) (list (+ x t2 ds 1.5 54 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 1.5 54 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) (list (+ x t2 ds 1.5 54 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 1.5 54 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) (list (+ x t2 ds 1.5 54 7 1.50 1.25 1.62 2.49) (+ (- y 25 0.70 1.73) 0.35 1.16 2.32) 0) layer "Continuous" 1)
          )
          ((= taille_antenne "91")
              (draw-rect (list (+ x t2 ds) (- y 25) 0) (list (+ x t2 ds 1.5) (- y 25 0.70) 0) layer)
              (draw-mtext (list (+ x t2 ds 0.75) (- y 28) 0) (strcat (rtos ds 2 2) "m") layer 2 0 10)

              (draw-line (list (+ x t2 ds) (- y 25) 0) (list (+ x t2 ds 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38) (- y 25) 0) (list (+ x t2 ds 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38) (- y 25) 0) (list (+ x t2 ds 0.38 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38 0.38) (- y 25) 0) (list (+ x t2 ds 1.5) (- y 25 0.70) 0) layer "Continuous" 1)

              (draw-line (list (+ x t2 ds) (- y 25 0.70) 0) (list (+ x t2 ds 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 0.38 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 0.38 0.38 0.38) (- y 25 0.70) 0) (list (+ x t2 ds 1.5) (- y 25) 0) layer "Continuous" 1)

              ;;91M
              (draw-line (list (+ x t2 ds 1.5) (- y 25 0.35) 0) (list (+ x t2 ds 1.5 84) (- y 25 0.35) 0) layer "Continuous" 1)
              (draw-line-color (list (+ x t2 ds 1.5 84) (- y 25 0.35) 0) (list (+ x t2 ds 1.5 84 7) (- y 25 0.35) 0) layer "Continuous" 1 130)
              (draw-mtext (list (+ x t2 ds 1.5 45.5) (- y 22) 0) nom_ant layer 2 0 10)

              (draw-rect (list (+ x t2 ds 1.5 84 7) (- y 25) 0) (list (+ x t2 ds 1.5 84 7 1.50) (- y 25 0.70) 0) layer)
              (draw-mtext (list (+ x t2 ds 0.75 92.5) (- y 28) 0) (strcat (rtos (+ ds 91) 2 2) "m") layer 2 0 10)

              (draw-line (list (+ x t2 ds 1.5 84 7 1.50) (+ (- y 25 0.70) 0.35) 0) (list (+ x t2 ds 1.5 84 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 1.5 84 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) (list (+ x t2 ds 1.5 84 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (+ x t2 ds 1.5 84 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) (list (+ x t2 ds 1.5 84 7 1.50 1.25 1.62 2.49) (+ (- y 25 0.70 1.73) 0.35 1.16 2.32) 0) layer "Continuous" 1)
          )
        )
    )
    (progn
        (cond
          ((= taille_antenne "31")
            (draw-rect (list (+ x 34 t2 ds) (- y 25) 0) (list (- (+ x 34 t2 ds) 1.5) (- y 25 0.70) 0) layer)
            (draw-mtext (list (- (+ x 34 t2 ds) 0.75 34) (- y 28) 0) (strcat (rtos ds 2 2) "m") layer 2 0 10)

            (draw-line (list (+ x 34 t2 ds) (- y 25) 0) (list (- (+ x 34 t2 ds) 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
            (draw-line (list (- (+ x 34 t2 ds) 0.38) (- y 25) 0) (list (- (+ x 34 t2 ds) 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
            (draw-line (list (- (+ x 34 t2 ds) 0.38 0.38) (- y 25) 0) (list (- (+ x 34 t2 ds) 0.38 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
            (draw-line (list (- (+ x 34 t2 ds) 0.38 0.38 0.38) (- y 25) 0) (list (- (+ x 34 t2 ds) 1.5) (- y 25 0.70) 0) layer "Continuous" 1)

            (draw-line (list (+ x 34 t2 ds) (- y 25 0.70) 0) (list (- (+ x 34 t2 ds) 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
            (draw-line (list (- (+ x 34 t2 ds) 0.38) (- y 25 0.70) 0) (list (- (+ x 34 t2 ds) 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
            (draw-line (list (- (+ x 34 t2 ds) 0.38 0.38) (- y 25 0.70) 0) (list (- (+ x 34 t2 ds) 0.38 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
            (draw-line (list (- (+ x 34 t2 ds) 0.38 0.38 0.38) (- y 25 0.70) 0) (list (- (+ x 34 t2 ds) 1.5) (- y 25) 0) layer "Continuous" 1)

            ;; 31M
            (draw-line (list (- (+ x 34 t2 ds) 1.5) (- y 25 0.35) 0) (list (- (+ x 34 t2 ds) 1.5 24) (- y 25 0.35) 0) layer "Continuous" 1)
            (draw-line-color (list (- (+ x 34 t2 ds) 1.5 24) (- y 25 0.35) 0) (list (- (+ x 34 t2 ds) 1.5 24 7) (- y 25 0.35) 0) layer "Continuous" 1 130)
            (draw-mtext (list (- (+ x 34 t2 ds) 1.5 15.5) (- y 22) 0) nom_ant layer 2 0 10)

            (draw-rect (list (- (+ x 34 t2 ds) 1.5 24 7) (- y 25) 0) (list (- (+ x 34 t2 ds) 1.5 24 7 1.50) (- y 25 0.70) 0) layer)
            (draw-mtext (list (- (+ x 34 t2 ds) 0.75) (- y 28) 0) (strcat (rtos (+ ds 31) 2 2) "m") layer 2 0 10)

            (draw-line (list (- (+ x 34 t2 ds) 1.5 24 7 1.50) (+ (- y 25 0.70) 0.35) 0) (list (- (+ x 34 t2 ds) 1.5 24 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) layer "Continuous" 1)
            (draw-line (list (- (+ x 34 t2 ds) 1.5 24 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) (list (- (+ x 34 t2 ds) 1.5 24 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) layer "Continuous" 1)
            (draw-line (list (- (+ x 34 t2 ds) 1.5 24 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) (list (- (+ x 34 t2 ds) 1.5 24 7 1.50 1.25 1.62 2.49) (+ (- y 25 0.70 1.73) 0.35 1.16 2.32) 0) layer "Continuous" 1)
          )
          ((= taille_antenne "61")
              (draw-rect (list (+ x 64 t2 ds) (- y 25) 0) (list (- (+ x 64 t2 ds) 1.5) (- y 25 0.70) 0) layer)
              (draw-mtext (list (- (+ x 64 t2 ds) 0.75 62.5) (- y 28) 0) (strcat (rtos ds 2 2) "m") layer 2 0 10)

              (draw-line (list (+ x 64 t2 ds) (- y 25) 0) (list (- (+ x 64 t2 ds) 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 64 t2 ds) 0.38) (- y 25) 0) (list (- (+ x 64 t2 ds) 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 64 t2 ds) 0.38 0.38) (- y 25) 0) (list (- (+ x 64 t2 ds) 0.38 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 64 t2 ds) 0.38 0.38 0.38) (- y 25) 0) (list (- (+ x 64 t2 ds) 1.5) (- y 25 0.70) 0) layer "Continuous" 1)

              (draw-line (list (+ x 64 t2 ds) (- y 25 0.70) 0) (list (- (+ x 64 t2 ds) 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 64 t2 ds) 0.38) (- y 25 0.70) 0) (list (- (+ x 64 t2 ds) 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 64 t2 ds) 0.38 0.38) (- y 25 0.70) 0) (list (- (+ x 64 t2 ds) 0.38 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 64 t2 ds) 0.38 0.38 0.38) (- y 25 0.70) 0) (list (- (+ x 64 t2 ds) 1.5) (- y 25) 0) layer "Continuous" 1)

              ;;61M
              (draw-line (list (- (+ x 64 t2 ds) 1.5) (- y 25 0.35) 0) (list (- (+ x 64 t2 ds) 1.5 54) (- y 25 0.35) 0) layer "Continuous" 1)
              (draw-line-color (list (- (+ x 64 t2 ds) 1.5 54) (- y 25 0.35) 0) (list (- (+ x 64 t2 ds) 1.5 54 7) (- y 25 0.35) 0) layer "Continuous" 1 130)
              (draw-mtext (list (- (+ x 64 t2 ds) 1.5 30.5) (- y 22) 0) nom_ant layer 2 0 10)

              (draw-rect (list (- (+ x 64 t2 ds) 1.5 54 7) (- y 25) 0) (list (- (+ x 64 t2 ds) 1.5 54 7 1.50) (- y 25 0.70) 0) layer)
              (draw-mtext (list (- (+ x 64 t2 ds) 0.75) (- y 28) 0) (strcat (rtos (+ ds 61) 2 2) "m") layer 2 0 10)

              (draw-line (list (- (+ x 64 t2 ds) 1.5 54 7 1.50) (+ (- y 25 0.70) 0.35) 0) (list (- (+ x 64 t2 ds) 1.5 54 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 64 t2 ds) 1.5 54 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) (list (- (+ x 64 t2 ds) 1.5 54 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 64 t2 ds) 1.5 54 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) (list (- (+ x 64 t2 ds) 1.5 54 7 1.50 1.25 1.62 2.49) (+ (- y 25 0.70 1.73) 0.35 1.16 2.32) 0) layer "Continuous" 1)
          )
          ((= taille_antenne "91")
              (draw-rect (list (+ x 94 t2 ds) (- y 25) 0) (list (- (+ x 94 t2 ds) 1.5) (- y 25 0.70) 0) layer)
              (draw-mtext (list (- (+ x 94 t2 ds) 0.75 92.5) (- y 28) 0) (strcat (rtos ds 2 2) "m") layer 2 0 10)

              (draw-line (list (+ x 94 t2 ds) (- y 25) 0) (list (- (+ x 94 t2 ds) 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 94 t2 ds) 0.38) (- y 25) 0) (list (- (+ x 94 t2 ds) 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 94 t2 ds) 0.38 0.38) (- y 25) 0) (list (- (+ x 94 t2 ds) 0.38 0.38 0.38) (- y 25 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 94 t2 ds) 0.38 0.38 0.38) (- y 25) 0) (list (- (+ x 94 t2 ds) 1.5) (- y 25 0.70) 0) layer "Continuous" 1)

              (draw-line (list (+ x 94 t2 ds) (- y 25 0.70) 0) (list (- (+ x 94 t2 ds) 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 94 t2 ds) 0.38) (- y 25 0.70) 0) (list (- (+ x 94 t2 ds) 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 94 t2 ds) 0.38 0.38) (- y 25 0.70) 0) (list (- (+ x 94 t2 ds) 0.38 0.38 0.38) (+ (- y 25 0.70) 0.70) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 94 t2 ds) 0.38 0.38 0.38) (- y 25 0.70) 0) (list (- (+ x 94 t2 ds) 1.5) (- y 25) 0) layer "Continuous" 1)

              ;;91M
              (draw-line (list (- (+ x 94 t2 ds) 1.5) (- y 25 0.35) 0) (list (- (+ x 94 t2 ds) 1.5 84) (- y 25 0.35) 0) layer "Continuous" 1)
              (draw-line-color (list (- (+ x 94 t2 ds) 1.5 84) (- y 25 0.35) 0) (list (- (+ x 94 t2 ds) 1.5 84 7) (- y 25 0.35) 0) layer "Continuous" 1 130)
              (draw-mtext (list (- (+ x 94 t2 ds) 1.5 45.5) (- y 22) 0) nom_ant layer 2 0 10)

              (draw-rect (list (- (+ x 94 t2 ds) 1.5 84 7) (- y 25) 0) (list (- (+ x 94 t2 ds) 1.5 84 7 1.50) (- y 25 0.70) 0) layer)
              (draw-mtext (list (- (+ x 94 t2 ds) 0.75) (- y 28) 0) (strcat (rtos (+ ds 91) 2 2) "m") layer 2 0 10)

              (draw-line (list (- (+ x 94 t2 ds) 1.5 84 7 1.50) (+ (- y 25 0.70) 0.35) 0) (list (- (+ x 94 t2 ds) 1.5 84 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 94 t2 ds) 1.5 84 7 1.50 1.25) (+ (- y 25 0.70) 0.35 1.16) 0) (list (- (+ x 94 t2 ds) 1.5 84 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) layer "Continuous" 1)
              (draw-line (list (- (+ x 94 t2 ds) 1.5 84 7 1.50 1.25 1.62) (+ (- y 25 0.70 1.73) 0.35 1.16) 0) (list (- (+ x 94 t2 ds) 1.5 84 7 1.50 1.25 1.62 2.49) (+ (- y 25 0.70 1.73) 0.35 1.16 2.32) 0) layer "Continuous" 1)
          )
        )  
    )
  )
)

(defun draw-crocodile (pt t2 ds layer / x y)
  (setq x (car pt))
  (setq y (cadr pt))

  (draw-mtext (list (- (+ x t2 ds) 4) (- y 22) 0) (strcat (rtos ds 2 2) "m") layer 2 0 10)
  (draw-line (list (+ x t2 ds) (- y 22) 0) (list (+ x t2 ds 0.5) (- y 21) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5) (- y 21) 0) (list (+ x t2 ds 0.5 1) (- y 21) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5 1) (- y 21) 0) (list (+ x t2 ds 0.5 1 0.5) (- y 21 0.5) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5 1 0.5) (- y 21 0.5) 0) (list (+ x t2 ds 0.5 1 0.5 0.5) (- y 21) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5 1 0.5 0.5) (- y 21) 0) (list (+ x t2 ds 0.5 1 0.5 0.5 1) (- y 21) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5 1 0.5 0.5 1) (- y 21) 0) (list (+ x t2 ds 0.5 1 0.5 0.5 1 0.5) (- y 21 1) 0) layer "Continuous" 1)

  (draw-line (list (+ x t2 ds) (- y 22 0.5) 0) (list (+ x t2 ds 0.5) (- y 21 0.5) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5) (- y 21 0.5) 0) (list (+ x t2 ds 0.5 1) (- y 21 0.5) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5 1) (- y 21 0.5) 0) (list (+ x t2 ds 0.5 1 0.5) (- y 21 0.5 0.5) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5 1 0.5) (- y 21 0.5 0.5) 0) (list (+ x t2 ds 0.5 1 0.5 0.5) (- y 21 0.5) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5 1 0.5 0.5) (- y 21 0.5) 0) (list (+ x t2 ds 0.5 1 0.5 0.5 1) (- y 21 0.5) 0) layer "Continuous" 1)
  (draw-line (list (+ x t2 ds 0.5 1 0.5 0.5 1) (- y 21 0.5) 0) (list (+ x t2 ds 0.5 1 0.5 0.5 1 0.5) (- y 21 1 0.5) 0) layer "Continuous" 1)
  (draw-mtext (list (+ x t2 ds 4 4) (- y 22) 0) (strcat (rtos (+ ds 4) 2 2) "m") layer 2 0 10)

)


(defun menu-ajout-equipements (pt t2 / choix ds_eq)
  (setq choix "")

  (while (/= choix "Q")
    (initget "P C A N O Q")
    (setq choix
      (getkword
        "\nAjouter un equipement ? [Pancarte/Camera/cAtenaire/aNtenne/crOcodile/Quitter] <Q> : "
      )
    )

    ;; Si Entrée, on quitte
    (if (null choix)
      (setq choix "Q")
    )

    (cond
      ;; Pancarte de signalisation
      ((= choix "P")
        (setq ds_eq (getreal "\nLa distance où se trouve la pancarte à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-pancarte pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ;; Camera
      ((= choix "C")
        (setq ds_eq (getreal "\nLa distance où se trouve la caméra à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-camera pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ;; Catenaire
      ((= choix "A")
        (setq ds_eq (getreal "\nLa distance où se trouve la catenaire à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-catenaire pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ;; Catenaire
      ((= choix "N")
        (setq ds_eq (getreal "\nLa distance où se trouve l'antenne à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-antenne pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ((= choix "O")
        (setq ds_eq (getreal "\nLa distance où se trouve le crocodile à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-crocodile pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ;; Quitter
      ((= choix "Q")
        (princ "\nFin de l'ajout des equipements.")
      )
    )
  )
)

(defun draw-quai (pt layer longueur t1 t2 / x y dp heurtoir)
  (setq x (car pt))
  (setq y (cadr pt))

  (draw-line (list x (- y t1) 0) (list x y 0) layer "ISO07W100" 0.25)
  (draw-line (list x y 0) (list (+ x t2) y 0) layer "ISO07W100" 0.25)

  (setq dp (getreal "\nEntrer la distance de depart <0> : "))

  (if (null dp)
    (setq dp 0)
  )

  (if (>= dp 0)
    (progn
      (draw-line (list (+ x t2) y 0) (list (+ x t2) (+ y 2) 0) layer "Continuous" 1)
      (draw-text (list (+ x t2) (+ y 5) 0) (strcat (rtos dp 2 2) "m") "0" 3 0)
    )
    (progn
      (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
      (exit)
    )
  )

  (draw-line (list (+ x t2) y 0) (list (+ x t2 longueur) y 0) layer "Continuous" 1)

  (initget "O N")
    (setq heurtoir (getkword "\nY a-t-il un heurtoir au bout du quai ? [Oui/Non] <N> : "))

    (if (= heurtoir "O")
      (progn
        (draw-line (list (+ x t2 longueur) y 0) (list (+ x t2 longueur) (+ y 7) 0) layer "Continuous" 1)

        (draw-line (list (+ x t2 longueur) (+ y 3.5) 0) (list (- (+ x t2 longueur) 1) (+ y 3.5) 0) layer "Continuous" 1)
        (draw-line (list (- (+ x t2 longueur) 1) (+ y 3.5) 0) (list (- (+ x t2 longueur) 1) (+ y 5.5) 0) layer "Continuous" 1)
        (draw-line (list (+ x t2 longueur) (+ y 5.5) 0) (list (- (+ x t2 longueur) 1) (+ y 5.5) 0) layer "Continuous" 1)

        (draw-line (list (+ x t2 longueur) (+ y 7) 0) (list (+ x t2 longueur 2) (+ y 7) 0) layer "Continuous" 1)
        (draw-line (list (+ x t2 longueur 2) (+ y 7) 0) (list (+ x t2 longueur 2) y 0) layer "Continuous" 1)

        (draw-mtext (list (+ x t2 longueur 10) y 0) (strcat "BQ:\\P" (rtos longueur 2 2) " m") "0" 3 0 20)
      )

      (progn
        (draw-line (list (+ x t2 longueur) y 0) (list (+ x t2 longueur) (- y T1) 0) layer "Continuous" 1)
        (draw-mtext (list (+ x t2 longueur 8) y 0) (strcat "BQ:\\P" (rtos longueur 2 2) " m") "0" 3 0 20 )
      )
    )
)


(defun c:S_QUAI (/ longueur pt x y heurtoir heurtoir_pt texte_pt)
  (make-layer "TL_MATERIEL_EXISTANT" 7)
  (make-layer "TL_MATERIEL_POSE" 12)
  (make-layer "TL_MATERIEL_REPOSE" 94)
  (make-layer "TL_MATERIEL_DEPOSE" 40)

  (setq longueur (getreal "\nEntrer la longueur du quai en metres : "))

  (if (and longueur (> longueur 0))
    (progn
      (setq pt (getpoint "\nCliquer le point de depart du quai : "))

      ;; Hauteurs graphiques des bandes

      (draw-quai pt "0" longueur 3 4)
      (princ "\nQuai cree avec succès")

      (menu-ajout-equipements pt 4)
      
    )
    (princ "\nErreur : la longueur doit etre superieure a 0.")
  )

  (princ)
)

(defun c:S_QUAI_EDIT (/ longueur pt x y heurtoir heurtoir_pt texte_pt)
  (setq pt (getpoint "\nPour modifier, cliquez sur le point de depart du quai (souvent à 0m) : "))

  (menu-ajout-equipements pt 0)

  (princ)
)

(defun c:S_EQP_QUAI (/ longueur pt x y heurtoir heurtoir_pt texte_pt)
  (setq pt (getpoint "\nCliquez sur le point ou ajouter des equipements : "))

  (menu-ajout-equipements pt 0)

  (princ)
)

(defun draw-camera-h (pt t2 ds layer / x y numero_cam) ;;Variable non def.
  (setq x (car pt))
  (setq y (cadr pt))

  (initget "H B HB")
  (setq c (getkword "\nL'orientation de la caméra ou des cameras ? [Haut/Bas/(HB)Haut-Bas] <H> : "))

  ;; Valeur par défaut : Haut
  (if (null c)
    (setq c "H")
  )

  (setq dq (getstring "\nLa distance par rapport aux bords du quai ? <...> : "))

  (if (= dq "")
    (setq dq "...")
  )

  (initget "E P R D")
  (setq s (getkword "\nLe statut de la caméra ou des caméras ? [Existant/Pose/Repose/Depose] <E> : "))

  (if (null s)
    (setq s "E")
  )

  (cond
    ((= s "E")
      (setq layer "TL_MATERIEL_EXISTANT")
    )

    ((= s "P")
      (setq layer "TL_MATERIEL_POSE")
    )

    ((= s "R")
      (setq layer "TL_MATERIEL_REPOSE")
    )

    ((= s "D")
      (setq layer "TL_MATERIEL_DEPOSE")
    )
  )

  (cond
  ;; HAUT
  ((= c "H")
    (progn
      (draw-line (list (+ x 13) (+ y ds) 0) (list (+ x 13 2.4) (+ y ds) 0) layer "Continuous" 1)
      (draw-line (list (+ x 13) (+ y ds) 0) (list (+ x 13 1.2) (- (+ y ds) 2.4) 0) layer "Continuous" 1)
      (draw-line (list (+ x 13 2.4) (+ y ds) 0) (list (+ x 13 1.2) (- (+ y ds) 2.4) 0) layer "Continuous" 1)

      (draw-rect (list (- (+ x 13) 1.2) (- (+ y ds) 2.4) 0) (list (+ x 13 3.6) (- (+ y ds) 2.4 9.6) 0) layer)

      (setq numero_cam (getstring T "\nEntrer le numéro de la camera (ex. C1) : "))  
      (if (= numero_cam "")
        (setq numero_cam "?")
      )

      (draw-text (list (+ x 11.8 2.4) (- (+ y ds) 7) 0) (strcat numero_cam) layer 2 0)
      (draw-mtext (list (+ x 13 1.2 3) (+ y ds 2) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

      (draw-cotlin-perso (list (+ x) (- (+ y ds) 9) 0) (list (+ x 11.80) (- (+ y ds) 9) 0) (strcat dq "m") layer)

      (initget "O N")
      (setq chmp (getkword "\nVoulez-vous afficher le champ de vision de la camera ? [Oui/Non] <O> : "))

      (if (null chmp)
        (setq chmp "O")
      )

      (cond
        ((= chmp "O")
          (hatch-poly4-color (list (+ x 88) (+ y ds) 0) (list (+ x 88 2.6 2.6) (+ y ds 13.5) 0) (list (+ x 88 2.6 2.6) (+ y ds 13.5 50) 0) (list (+ x 88) (+ y ds 13.5 50) 0) layer 231) 
          (draw-poly4 (list (+ x 88) (+ y ds) 0) (list (+ x 88 2.6 2.6) (+ y ds 13.5) 0) (list (+ x 88 2.6 2.6) (+ y ds 13.5 50) 0) (list (+ x 88) (+ y ds 13.5 50) 0) layer) 
          (draw-mtext (list (+ x 88 2.6) (+ y ds 31.75) 0) numero_cam layer 2 0 20)
        )
      )

      (initget "M S R")
      (setq h_q (getkword "\nSur quoi la camera est-elle accrochée ? [Mat/Suspente/Rien] <M> : "))

      (if (null h_q)
        (setq h_q "M")
      )

      (cond
        ((= h_q "M")
          (setq h_cam_no_m "")
          (setq h_cam (getreal "\nLa hauteur de la camera en m (ex. 1.5) : "))
         

          ;; QUAI
          (draw-line (list (+ x 33) (- (+ y ds) 16.42) 0) (list (+ x 33 10) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (+ x 30) (- (+ y ds) 16.42) 0) "Quai" layer 2 0 15)

          ;; MAT
          (draw-line (list (+ x 33 10 2.34) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 3.60) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 1.20) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20) (- (+ y ds 1.20) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42 0.37) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46) 16.42) 0) layer)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22 0.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.80) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)

          ;; CAM
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (- (+ x 33 10 2.34 1.20 0.24 0.24 1.63) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62 1.5) 16.42) 0) numero_cam layer 2 0 20)

          (if (null h_cam)
            ;; SI h_cam est nil
            (progn
              (setq h_cam_no_m "")
              (draw-cotlin-perso
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
                "...m"
                layer
              )
            )

            ;; SINON h_cam existe
            (draw-cotlin-perso
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
              (strcat (rtos h_cam 2 2) "m")
              layer
            )
          )
        )

        ((= h_q "S")
          (setq h_cam_no_m "")
          (setq h_cam (getreal "\nLa hauteur de la camera en m (ex. 1.5) : "))
         

          ;; QUAI
          (draw-line (list (+ x 33) (- (+ y ds) 16.42) 0) (list (+ x 33 10) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (+ x 30) (- (+ y ds) 16.42) 0) "Quai" layer 2 0 15)

          ;; MAT
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)

          (draw-rect (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) layer)
          (hatch-poly4-pattern (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) layer 7 "ANSI31" 0.25)

          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) layer "Continuous" 1)


          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42 0.37) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46) 16.42) 0) layer)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22 0.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.80) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)

          ;; CAM
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (- (+ x 33 10 2.34 1.20 0.24 0.24 1.63) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62 1.5) 16.42) 0) numero_cam layer 2 0 20)

          (if (null h_cam)
            ;; SI h_cam est nil
            (progn
              (setq h_cam_no_m "")
              (draw-cotlin-perso
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
                "...m"
                layer
              )
            )

            ;; SINON h_cam existe
            (draw-cotlin-perso
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
              (strcat (rtos h_cam 2 2) "m")
              layer
            )
          )
        )
      )
    )
  )

  ;; BAS
  ((= c "B")
    (progn
      (draw-line (list (+ x 13) (+ y ds) 0) (list (+ x 13 2.4) (+ y ds) 0) layer "Continuous" 1)
      (draw-line (list (+ x 13) (+ y ds) 0) (list (+ x 13 1.2) (+ y ds 2.4) 0) layer "Continuous" 1)
      (draw-line (list (+ x 13 2.4) (+ y ds) 0) (list (+ x 13 1.2) (+ y ds 2.4) 0) layer "Continuous" 1)

      (draw-rect (list (- (+ x 13) 1.2) (+ y ds 2.4) 0) (list (+ x 13 3.6) (+ y ds 2.4 9.6) 0) layer)

      (setq numero_cam (getstring T "\nEntrer le numéro de la camera (ex. C1) : "))  
      (if (= numero_cam "")
        (setq numero_cam "?")
      )

      (draw-text (list (+ x 11.8 2.4) (+ y ds 7) 0) (strcat numero_cam) layer 2 0)
      (draw-mtext (list (+ x 13 1.2 3) (- (+ y ds) 2) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

      (draw-cotlin-perso (list (+ x) (+ y ds 5) 0) (list (+ x 11.80) (+ y ds 5) 0) (strcat (rtos dq 2 2) "m") layer)

      (initget "O N")
      (setq chmp (getkword "\nVoulez-vous afficher le champ de vision de la camera ? [Oui/Non] <O> : "))

      (if (null chmp)
        (setq chmp "O")
      )

      (cond
        ((= chmp "O")
          (hatch-poly4-color (list (+ x 88 5.20) (+ y ds) 0) (list (+ x 88 5.20 2.6 2.6) (- (+ y ds) 13.5) 0) (list (+ x 88 5.20 2.6 2.6) (- (+ y ds) 13.5 50) 0) (list (+ x 88 5.20) (- (+ y ds) 13.5 50) 0) layer 231) 
          (draw-poly4 (list (+ x 88 5.20) (+ y ds) 0) (list (+ x 88 5.20 2.6 2.6) (- (+ y ds) 13.5) 0) (list (+ x 88 5.20 2.6 2.6) (- (+ y ds) 13.5 50) 0) (list (+ x 88 5.20) (- (+ y ds) 13.5 50) 0) layer) 
          (draw-mtext (list (+ x 88 5.20 2.6) (- (+ y ds) 31.75) 0) numero_cam layer 2 0 20)
        )
      )

      (initget "M S R")
      (setq h_q (getkword "\nSur quoi la camera est-elle accrochée ? [Mat/Suspente/Rien] <M> : "))

      (if (null h_q)
        (setq h_q "M")
      )

      (cond
        ((= h_q "M")
          (setq h_cam_no_m "")
          (setq h_cam (getreal "\nLa hauteur de la camera en m (ex. 1.5) : "))
         

          ;; QUAI
          (draw-line (list (+ x 33) (- (+ y ds) 16.42) 0) (list (+ x 33 10) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (+ x 30) (- (+ y ds) 16.42) 0) "Quai" layer 2 0 15)

          ;; MAT
          (draw-line (list (+ x 33 10 2.34) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 3.60) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 1.20) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20) (- (+ y ds 1.20) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42 0.37) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46) 16.42) 0) layer)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22 0.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.80) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)

          ;; CAM
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (- (+ x 33 10 2.34 1.20 0.24 0.24 1.63) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62 1.5) 16.42) 0) numero_cam layer 2 0 20)

          (if (null h_cam)
            ;; SI h_cam est nil
            (progn
              (setq h_cam_no_m "")
              (draw-cotlin-perso
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
                "...m"
                layer
              )
            )

            ;; SINON h_cam existe
            (draw-cotlin-perso
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
              (strcat (rtos h_cam 2 2) "m")
              layer
            )
          )
        )

        ((= h_q "S")
          (setq h_cam_no_m "")
          (setq h_cam (getreal "\nLa hauteur de la camera en m (ex. 1.5) : "))
         

          ;; QUAI
          (draw-line (list (+ x 33) (- (+ y ds) 16.42) 0) (list (+ x 33 10) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (+ x 30) (- (+ y ds) 16.42) 0) "Quai" layer 2 0 15)

          ;; MAT
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)

          (draw-rect (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) layer)
          (hatch-poly4-pattern (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) layer 7 "ANSI31" 0.25)

          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) layer "Continuous" 1)


          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42 0.37) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46) 16.42) 0) layer)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22 0.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.80) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)

          ;; CAM
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (- (+ x 33 10 2.34 1.20 0.24 0.24 1.63) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62 1.5) 16.42) 0) numero_cam layer 2 0 20)

          (if (null h_cam)
            ;; SI h_cam est nil
            (progn
              (setq h_cam_no_m "")
              (draw-cotlin-perso
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
                "...m"
                layer
              )
            )

            ;; SINON h_cam existe
            (draw-cotlin-perso
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
              (strcat (rtos h_cam 2 2) "m")
              layer
            )
          )
        )
      )

    )
  )

  ;; HAUT-BAS
  ((= c "HB")
    (progn
      ;; HAUT
      (draw-line (list (+ x 13) (+ y ds) 0) (list (+ x 13 2.4) (+ y ds) 0) layer "Continuous" 1)
      (draw-line (list (+ x 13) (+ y ds) 0) (list (+ x 13 1.2) (- (+ y ds) 2.4) 0) layer "Continuous" 1)
      (draw-line (list (+ x 13 2.4) (+ y ds) 0) (list (+ x 13 1.2) (- (+ y ds) 2.4) 0) layer "Continuous" 1)

      (draw-rect (list (- (+ x 13) 1.2) (- (+ y ds) 2.4) 0) (list (+ x 13 3.6) (- (+ y ds) 2.4 9.6) 0) layer)

      (setq numero_cam_1 (getstring T "\nEntrer le numéro de la camera du haut (ex. C2) : "))  
      (if (= numero_cam_1 "")
        (setq numero_cam_1 "?")
      )

      (draw-text (list (+ x 11.8 2.4) (- (+ y ds) 7) 0) (strcat numero_cam_1) layer 2 0)
      (draw-mtext (list (+ x 13 1.2 1.2 6 4.80) (+ y ds) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

      (draw-cotlin-perso (list (+ x) (- (+ y ds) 9) 0) (list (+ x 11.80) (- (+ y ds) 9) 0) (strcat (rtos dq 2 2) "m") layer)

      (initget "O N")
      (setq chmp (getkword "\nVoulez-vous afficher le champ de vision de la camera du haut ? [Oui/Non] <O> : "))

      (if (null chmp)
        (setq chmp "O")
      )

      (cond
        ((= chmp "O")
          (hatch-poly4-color (list (+ x 88) (+ y ds) 0) (list (+ x 88 2.6 2.6) (+ y ds 13.5) 0) (list (+ x 88 2.6 2.6) (+ y ds 13.5 50) 0) (list (+ x 88) (+ y ds 13.5 50) 0) layer 231) 
          (draw-poly4 (list (+ x 88) (+ y ds) 0) (list (+ x 88 2.6 2.6) (+ y ds 13.5) 0) (list (+ x 88 2.6 2.6) (+ y ds 13.5 50) 0) (list (+ x 88) (+ y ds 13.5 50) 0) layer) 
          (draw-mtext (list (+ x 88 2.6) (+ y ds 31.75) 0) numero_cam_1 layer 2 0 20)
        )
      )

      ;; BAS

      (draw-line (list (+ x 13 4.80) (+ y ds) 0) (list (+ x 13 2.4 4.80) (+ y ds) 0) layer "Continuous" 1)
      (draw-line (list (+ x 13 4.80) (+ y ds) 0) (list (+ x 13 1.2 4.80) (+ y ds 2.4) 0) layer "Continuous" 1)
      (draw-line (list (+ x 13 2.4 4.80) (+ y ds) 0) (list (+ x 13 1.2 4.80) (+ y ds 2.4) 0) layer "Continuous" 1)

      (draw-rect (list (- (+ x 13 4.80) 1.2) (+ y ds 2.4) 0) (list (+ x 13 3.6 4.80) (+ y ds 2.4 9.6) 0) layer)

      (setq numero_cam_2 (getstring T "\nEntrer le numéro de la camera (ex. C1) : "))  
      (if (= numero_cam_2 "")
        (setq numero_cam_2 "?")
      )

      (draw-text (list (+ x 11.8 2.4 4.80) (+ y ds 7) 0) (strcat numero_cam_2) layer 2 0)

      (draw-cotlin-perso (list (+ x) (+ y ds 5) 0) (list (+ x 11.80 4.80) (+ y ds 5) 0) (strcat (rtos dq 2 2) "m") layer)

      (initget "O N")
      (setq chmp (getkword "\nVoulez-vous afficher le champ de vision de la camera ? [Oui/Non] <O> : "))

      (if (null chmp)
        (setq chmp "O")
      )

      (cond
        ((= chmp "O")
          (hatch-poly4-color (list (+ x 88 5.20) (+ y ds) 0) (list (+ x 88 5.20 2.6 2.6) (- (+ y ds) 13.5) 0) (list (+ x 88 5.20 2.6 2.6) (- (+ y ds) 13.5 50) 0) (list (+ x 88 5.20) (- (+ y ds) 13.5 50) 0) layer 231) 
          (draw-poly4 (list (+ x 88 5.20) (+ y ds) 0) (list (+ x 88 5.20 2.6 2.6) (- (+ y ds) 13.5) 0) (list (+ x 88 5.20 2.6 2.6) (- (+ y ds) 13.5 50) 0) (list (+ x 88 5.20) (- (+ y ds) 13.5 50) 0) layer) 
          (draw-mtext (list (+ x 88 5.20 2.6) (- (+ y ds) 31.75) 0) numero_cam_2 layer 2 0 20)
        )
      )

      (initget "M S R")
      (setq h_q (getkword "\nSur quoi la camera est-elle accrochée ? [Mat/Suspente/Rien] <M> : "))

      (if (null h_q)
        (setq h_q "M")
      )

      (cond
        ((= h_q "M")
          (setq h_cam_no_m "")
          (setq h_cam (getreal "\nLa hauteur de la camera en m (ex. 1.5) : "))
         

          ;; QUAI
          (draw-line (list (+ x 33) (- (+ y ds) 16.42) 0) (list (+ x 33 10) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (+ x 30) (- (+ y ds) 16.42) 0) "Quai" layer 2 0 15)

          ;; MAT
          (draw-line (list (+ x 33 10 2.34) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 3.60) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 1.20) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds) 16.42) 0) (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20) (- (+ y ds 1.20) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 1.20) (- (+ y ds 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42 0.37) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46) 16.42) 0) layer)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22 0.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.80) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)

          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40 1.20) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40 1.20) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22 0.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 1.20) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.80 1.20) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)

          ;; CAM
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (- (+ x 33 10 2.34 1.20 0.24 0.24 1.63) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62 1.5) 16.42) 0) (strcat numero_cam_1 " - " numero_cam_2) layer 2 0 20)

          (if (null h_cam)
            ;; SI h_cam est nil
            (progn
              (setq h_cam_no_m "")
              (draw-cotlin-perso
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
                "...m"
                layer
              )
            )

            ;; SINON h_cam existe
            (draw-cotlin-perso
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
              (strcat (rtos h_cam 2 2) "m")
              layer
            )
          )
        )

        ((= h_q "S")
          (setq h_cam_no_m "")
          (setq h_cam (getreal "\nLa hauteur de la camera en m (ex. 1.5) : "))
         

          ;; QUAI
          (draw-line (list (+ x 33) (- (+ y ds) 16.42) 0) (list (+ x 33 10) (- (+ y ds) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (+ x 30) (- (+ y ds) 16.42) 0) "Quai" layer 2 0 15)

          ;; MAT
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) layer "Continuous" 1)

          (draw-rect (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) layer)
          (hatch-poly4-pattern (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 1.20 2) 0.24 0.24 0.24 2 2) (- (+ y ds 1.20 10.80 9.60 1) 16.42) 0) layer 7 "ANSI31" 0.25)

          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (+ x 33 10 2.34 1.20 0.24 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) layer "Continuous" 1)


          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (+ x 33 10 2.34 1.20 0.24 0.24) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 1.20) 16.42 0.37) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18) (- (+ y ds 1.20 10.80 4.80 0.37) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46) 16.42) 0) layer)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22 0.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.80) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)

          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40 1.20) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.40 1.20) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.22 0.80) 16.42) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24 1.20) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24 0.80 1.20) 2.18 3.20) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)

          ;; CAM
          (draw-line (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) (list (- (+ x 33 10 2.34 1.20 0.24 0.24) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62) 16.42) 0) layer "Continuous" 1)
          (draw-mtext (list (- (+ x 33 10 2.34 1.20 0.24 0.24 1.63) 2.18 3.20 1.30 3.25) (- (+ y ds 1.20 10.80 4.80 0.37 0.46 0.62 1.5) 16.42) 0) (strcat numero_cam_1 " - " numero_cam_2) layer 2 0 20)

          (if (null h_cam)
            ;; SI h_cam est nil
            (progn
              (setq h_cam_no_m "")
              (draw-cotlin-perso
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
                (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
                "...m"
                layer
              )
            )

            ;; SINON h_cam existe
            (draw-cotlin-perso
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds) 16.42) 0)
              (list (- (+ x 33 5.71) 1.93) (- (+ y ds 18.25) 16.42) 0)
              (strcat (rtos h_cam 2 2) "m")
              layer
            )
          )
        )
      )

    )
  )
  )
)

(defun draw-pancarte-h (pt t2 ds layer / x y c)
  (setq x (car pt))
  (setq y (cadr pt))

  (initget "1 2 3")
  (setq c (getkword "\nQuel type de pancarte ? (1 - Une pancarte / 2 - Deux pancartes côte à côte / 3 - Deux pancartes l'une au-dessus de l'autre) [1/2/3] <1> : "))

  ;; Valeur par défaut : 1
  (if (null c)
    (setq c "1")
  )

  (cond
    ((= c "1")

      (initget "M S")
      (setq h_q (getkword "\nSur quoi la pancarte est-elle accrochée ? [Mat/Suspente] <M> : "))

      (if (null h_q)
        (setq h_q "M")
      )

      (cond
        ((= h_q "M")
          (draw-line-ep (list (+ x 12.20) (+ y ds) 0) (list (+ x 12.20 4) (+ y ds) 0) layer "Continuous" 1 0.60)
          (draw-line (list (+ x 12.20 4) (+ y ds) 0) (list (+ x 12.20 4 3.3) (+ y ds) 0) layer "Continuous" 1)
          (draw-circle (list (+ x 12.20 4 3.3 1.3) (+ y ds) 0) 1.3 layer)
          (draw-line (list (+ x 12.20 4 3.3 0.65) (+ y ds 1.13) 0) (list (+ x 12.20 4 3.3 1.95) (- (+ y ds) 1.13) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 4 3.3 0.65) (- (+ y ds) 1.13) 0) (list (+ x 12.20 4 3.3 1.95) (+ y ds 1.13) 0) layer "Continuous" 1)
          (draw-circle (list (+ x 12.20 4 3.3 2.6 2) (+ y ds) 0) 2 layer)
          (draw-circle (list (+ x 12.20 4 3.3 2.6 2 2 1.3) (+ y ds) 0) 1.3 layer)
          (draw-line (list (+ x 12.20 4 3.3 0.65 6.61) (+ y ds 1.13) 0) (list (+ x 12.20 4 3.3 1.95 6.61) (- (+ y ds) 1.13) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 4 3.3 0.65 6.61) (- (+ y ds) 1.13) 0) (list (+ x 12.20 4 3.3 1.95 6.61) (+ y ds 1.13) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 12.20 4 3.3 2.6 2 2 1.3 1) (- (+ y ds) 3) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (+ x 12.20 2 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.96) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)

          (setq texte_pancarte
          (getstring T "\nEntrer le texte de la pancarte  (\\ pour sauter une ligne) <-> : "))

          (if (= texte_pancarte "")
            (setq texte_pancarte "-")
          )

          (draw-mtext (list (- (+ x 12.20 2 0.48 2) 0.48 4) (+ y ds 1 0.96 3.36 1 1 1) 0) texte_pancarte layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (- (+ y ds) 1) 0) (list (+ x 12.20 2) (- (+ y ds) 1 2.50) 0) layer "Continuous" 1)

          (setq ds_p "")
          (setq ds_p (getstring "\nLa distance par rapport aux bords du quai ? (ex: 1.5) <...> : "))

          (if (= ds_p "")
            (setq ds_p "...")
          )

          (draw-cotlin-perso
                  (list (- (+ x 12.20 2.5) 14.20 0.5) (- (+ y ds) 1 1.25 2) 0)
                  (list (- (+ x 12.20 2.5) 0.5) (- (+ y ds) 1 1.25 2) 0)
                  (strcat ds_p "m")
                  layer
          )

          (draw-line (list (+ x 44.24) (- (+ y ds) 4.10) 0) (list (+ x 44.24 3.60) (- (+ y ds) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 1.43 0.16) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) (list (- (+ x 44.24 2.17) 0.16) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.59) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.59 0.42) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)

          (draw-rect (list (+ x 37.85) (+ y ds 4.34) 0) (list (+ x 41.84) (+ y ds 0.30) 0) layer)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 1.01) 0) (list (+ x 41.84 3.93) (+ y ds 0.30 1.01) 0) layer "Continuous" 1)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 3.03) 0) (list (+ x 41.84 3.96) (+ y ds 0.30 3.03) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 39.84) (+ y ds 2.32) 0) texte_pancarte layer 1 0 20)
        )
        ((= h_q "S")
          (draw-line-ep (list (+ x 12.20) (+ y ds) 0) (list (+ x 12.20 4) (+ y ds) 0) layer "Continuous" 1 0.60)
          (draw-line (list (+ x 12.20 4) (+ y ds) 0) (list (+ x 12.20 4 3.3) (+ y ds) 0) layer "Continuous" 1)
          (draw-rect (list (+ x 12.20 4 3.3) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (- (+ y ds) 1.5) 0) layer)
          (hatch-poly4-pattern (list (+ x 12.20 4 3.3) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (- (+ y ds) 1.5) 0) (list (+ x 12.20 4 3.3) (- (+ y ds) 1.5) 0) layer 7 "ANSI31" 0.25)

          (draw-mtext (list (+ x 12.20 4 3.3 2.6 2 2 1.3 1) (- (+ y ds) 3) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (+ x 12.20 2 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.96) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)

          (setq texte_pancarte
          (getstring T "\nEntrer le texte de la pancarte  (\\ pour sauter une ligne) <-> : "))

          (if (= texte_pancarte "")
            (setq texte_pancarte "-")
          )

          (draw-mtext (list (- (+ x 12.20 2 0.48 2) 0.48 4) (+ y ds 1 0.96 3.36 1 1 1) 0) texte_pancarte layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (- (+ y ds) 1) 0) (list (+ x 12.20 2) (- (+ y ds) 1 2.50) 0) layer "Continuous" 1)

          (setq ds_p "")
          (setq ds_p (getstring "\nLa distance par rapport aux bords du quai ? (ex: 1.5) <...> : "))

          (if (= ds_p "")
            (setq ds_p "...")
          )

          (draw-cotlin-perso
                  (list (- (+ x 12.20 2.5) 14.20 0.5) (- (+ y ds) 1 1.25 2) 0)
                  (list (- (+ x 12.20 2.5) 0.5) (- (+ y ds) 1 1.25 2) 0)
                  (strcat ds_p "m")
                  layer
          )

          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 1.43) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) (list (+ x 44.24 2.17) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 44.24 1.43) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.43 2.37) (- (+ y ds 9.10 2) 4.10) 0) layer)
          (hatch-poly4-pattern (list (- (+ x 44.24 1.43) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (- (+ x 44.24 1.43 4) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.43 2.37) (- (+ y ds 9.10 2) 4.10) 0) (list (- (+ x 44.24 1.43 2.37) 4) (- (+ y ds 9.10 2) 4.10) 0) layer 7 "ANSI31" 0.25)

          (draw-rect (list (+ x 37.85) (+ y ds 4.34) 0) (list (+ x 41.84) (+ y ds 0.30) 0) layer)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 1.01) 0) (list (+ x 41.84 3.83) (+ y ds 0.30 1.01) 0) layer "Continuous" 1)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 3.03) 0) (list (+ x 41.84 3.83) (+ y ds 0.30 3.03) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 39.84) (+ y ds 2.32) 0) texte_pancarte layer 1 0 20)
        )
      )
    )

    ((= c "2")
      (initget "M S")
      (setq h_q (getkword "\nSur quoi les pancartes sont-elle accrochées ? [Mat/Suspente] <M> : "))

      (if (null h_q)
        (setq h_q "M")
      )

      (cond
        ((= h_q "M")
          (draw-line-ep (list (+ x 8.20) (+ y ds) 0) (list (+ x 8.20 4) (+ y ds) 0) layer "Continuous" 1 0.60)
          (draw-line-ep (list (+ x 12.20) (+ y ds) 0) (list (+ x 12.20 4) (+ y ds) 0) layer "Continuous" 1 0.60)
          (draw-line (list (+ x 12.20 4) (+ y ds) 0) (list (+ x 12.20 4 3.3) (+ y ds) 0) layer "Continuous" 1)
          (draw-circle (list (+ x 12.20 4 3.3 1.3) (+ y ds) 0) 1.3 layer)
          (draw-line (list (+ x 12.20 4 3.3 0.65) (+ y ds 1.13) 0) (list (+ x 12.20 4 3.3 1.95) (- (+ y ds) 1.13) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 4 3.3 0.65) (- (+ y ds) 1.13) 0) (list (+ x 12.20 4 3.3 1.95) (+ y ds 1.13) 0) layer "Continuous" 1)
          (draw-circle (list (+ x 12.20 4 3.3 2.6 2) (+ y ds) 0) 2 layer)
          (draw-circle (list (+ x 12.20 4 3.3 2.6 2 2 1.3) (+ y ds) 0) 1.3 layer)
          (draw-line (list (+ x 12.20 4 3.3 0.65 6.61) (+ y ds 1.13) 0) (list (+ x 12.20 4 3.3 1.95 6.61) (- (+ y ds) 1.13) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 4 3.3 0.65 6.61) (- (+ y ds) 1.13) 0) (list (+ x 12.20 4 3.3 1.95 6.61) (+ y ds 1.13) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 12.20 4 3.3 2.6 2 2 1.3 1) (- (+ y ds) 3) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (+ x 12.20 2 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.96) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)

          (draw-line (list (- (+ x 12.20 2) 4) (+ y ds 1) 0) (list (- (+ x 12.20 2) 0.48 4) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 4) (+ y ds 1) 0) (list (- (+ x 12.20 2 0.48) 4) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 0.48 4) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.96) 0.48 4) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 1.68) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 1.68) 0) (list (- (+ x 12.20 2 0.48) 0.48 4 4) (+ y ds 1 0.96 1.68) 0) layer "Continuous" 1)

          (setq texte_pancarte_2
          (getstring T "\nEntrer le texte de la premiere pancarte  (\\ pour sauter une ligne) : "))

          (if (= texte_pancarte_2 "")
            (setq texte_pancarte_2 "-")
          )

          (setq texte_pancarte_1
          (getstring T "\nEntrer le texte de la deuxieme pancarte  (\\ pour sauter une ligne) : "))

          (if (= texte_pancarte_1 "")
            (setq texte_pancarte_1 "-")
          )

          (draw-mtext (list (- (+ x 12.20 2 0.48 2) 0.48 4) (+ y ds 1 0.96 3.36 1 1 1) 0) texte_pancarte_1 layer 2 0 20)
          (draw-mtext (list (- (+ x 12.20 2 0.48 2) 0.48 4 4) (- (+ y ds 1 0.96 3.36 1 1 1) 1.68) 0) texte_pancarte_2 layer 2 0 20)

          (draw-line (list (- (+ x 12.20 2) 4) (- (+ y ds) 1) 0) (list (- (+ x 12.20 2) 4) (- (+ y ds) 1 2.50) 0) layer "Continuous" 1)

          (setq ds_p "")
          (setq ds_p (getstring "\nLa distance de la premiere pancarte par rapport aux bords du quai ? (ex: 1.5) <...> : "))

          (if (= ds_p "")
            (setq ds_p "...")
          )

          (draw-cotlin-perso-taille
                  (list (- (+ x 12.20 2.5) 10.20 0.5 4) (- (+ y ds) 1 1.25 2) 0)
                  (list (- (+ x 12.20 2.5) 0.5 4) (- (+ y ds) 1 1.25 2) 0)
                  (strcat ds_p "m")
                  layer
                  2
          )

          (draw-line (list (+ x 44.24) (- (+ y ds) 4.10) 0) (list (+ x 44.24 3.60) (- (+ y ds) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 1.43 0.16) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) (list (- (+ x 44.24 2.17) 0.16) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.59) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.59 0.42) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          ;;P1
          (draw-rect (list (+ x 37.85) (+ y ds 4.34) 0) (list (+ x 41.84) (+ y ds 0.30) 0) layer)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 1.01) 0) (list (+ x 41.84 3.93) (+ y ds 0.30 1.01) 0) layer "Continuous" 1)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 3.03) 0) (list (+ x 41.84 3.96) (+ y ds 0.30 3.03) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 39.84) (+ y ds 2.32) 0) texte_pancarte_1 layer 1 0 20)
          ;;P2
          (draw-rect (list (- (+ x 37.85) 3.99) (+ y ds 4.34) 0) (list (- (+ x 41.84) 3.99) (+ y ds 0.30) 0) layer)
          (draw-mtext (list (- (+ x 39.84) 3.99) (+ y ds 2.32) 0) texte_pancarte_2 layer 1 0 20)
        )
        ((= h_q "S")
          (draw-line-ep (list (+ x 8.20) (+ y ds) 0) (list (+ x 8.20 4) (+ y ds) 0) layer "Continuous" 1 0.60)
          (draw-line-ep (list (+ x 12.20) (+ y ds) 0) (list (+ x 12.20 4) (+ y ds) 0) layer "Continuous" 1 0.60)
          (draw-line (list (+ x 12.20 4) (+ y ds) 0) (list (+ x 12.20 4 3.3) (+ y ds) 0) layer "Continuous" 1)
          (draw-rect (list (+ x 12.20 4 3.3) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (- (+ y ds) 1.5) 0) layer)
          (hatch-poly4-pattern (list (+ x 12.20 4 3.3) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (- (+ y ds) 1.5) 0) (list (+ x 12.20 4 3.3) (- (+ y ds) 1.5) 0) layer 7 "ANSI31" 0.25)

          (draw-mtext (list (+ x 12.20 4 3.3 2.6 2 2 1.3 1) (- (+ y ds) 3) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (+ x 12.20 2 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.96) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)
          
          (draw-line (list (- (+ x 12.20 2) 4) (+ y ds 1) 0) (list (- (+ x 12.20 2) 0.48 4) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 4) (+ y ds 1) 0) (list (- (+ x 12.20 2 0.48) 4) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 0.48 4) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.96) 0.48 4) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 1.68) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 1.68) 0) (list (- (+ x 12.20 2 0.48) 0.48 4 4) (+ y ds 1 0.96 1.68) 0) layer "Continuous" 1)

          (setq texte_pancarte_2
          (getstring T "\nEntrer le texte de la premiere pancarte  (\\ pour sauter une ligne) : "))

          (if (= texte_pancarte_2 "")
            (setq texte_pancarte_2 "-")
          )

          (setq texte_pancarte_1
          (getstring T "\nEntrer le texte de la deuxieme pancarte  (\\ pour sauter une ligne) : "))

          (if (= texte_pancarte_1 "")
            (setq texte_pancarte_1 "-")
          )

          (draw-mtext (list (- (+ x 12.20 2 0.48 2) 0.48 4) (+ y ds 1 0.96 3.36 1 1 1) 0) texte_pancarte_1 layer 2 0 20)
          (draw-mtext (list (- (+ x 12.20 2 0.48 2) 0.48 4 4) (- (+ y ds 1 0.96 3.36 1 1 1) 1.68) 0) texte_pancarte_2 layer 2 0 20)

          (draw-line (list (- (+ x 12.20 2) 4) (- (+ y ds) 1) 0) (list (- (+ x 12.20 2) 4) (- (+ y ds) 1 2.50) 0) layer "Continuous" 1)

          (setq ds_p "")
          (setq ds_p (getstring "\nLa distance de la premiere pancartepar rapport aux bords du quai ? (ex: 1.5) <...> : "))

          (if (= ds_p "")
            (setq ds_p "...")
          )

          (draw-cotlin-perso-taille
                  (list (- (+ x 12.20 2.5) 10.20 0.5 4) (- (+ y ds) 1 1.25 2) 0)
                  (list (- (+ x 12.20 2.5) 0.5 4) (- (+ y ds) 1 1.25 2) 0)
                  (strcat ds_p "m")
                  layer
                  2
          )

          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 1.43) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) (list (+ x 44.24 2.17) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 44.24 1.43) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.43 2.37) (- (+ y ds 9.10 2) 4.10) 0) layer)
          (hatch-poly4-pattern (list (- (+ x 44.24 1.43) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (- (+ x 44.24 1.43 4) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.43 2.37) (- (+ y ds 9.10 2) 4.10) 0) (list (- (+ x 44.24 1.43 2.37) 4) (- (+ y ds 9.10 2) 4.10) 0) layer 7 "ANSI31" 0.25)
          ;;P1
          (draw-rect (list (+ x 37.85) (+ y ds 4.34) 0) (list (+ x 41.84) (+ y ds 0.30) 0) layer)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 1.01) 0) (list (+ x 41.84 3.83) (+ y ds 0.30 1.01) 0) layer "Continuous" 1)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 3.03) 0) (list (+ x 41.84 3.83) (+ y ds 0.30 3.03) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 39.84) (+ y ds 2.32) 0) texte_pancarte_1 layer 1 0 20)
          ;;P2
          (draw-rect (list (- (+ x 37.85) 3.99) (+ y ds 4.34) 0) (list (- (+ x 41.84) 3.99) (+ y ds 0.30) 0) layer)
          (draw-mtext (list (- (+ x 39.84) 3.99) (+ y ds 2.32) 0) texte_pancarte_2 layer 1 0 20)
        )
      )
    )

    ((= c "3")
      (initget "M S")
      (setq h_q (getkword "\nSur quoi les pancartes sont-elle accrochées ? [Mat/Suspente] <M> : "))

      (if (null h_q)
        (setq h_q "M")
      )

      (cond
        ((= h_q "M")
          (draw-line-ep (list (+ x 12.20) (+ y ds) 0) (list (+ x 12.20 4) (+ y ds) 0) layer "Continuous" 1 0.60)
          (draw-line (list (+ x 12.20 4) (+ y ds) 0) (list (+ x 12.20 4 3.3) (+ y ds) 0) layer "Continuous" 1)
          (draw-circle (list (+ x 12.20 4 3.3 1.3) (+ y ds) 0) 1.3 layer)
          (draw-line (list (+ x 12.20 4 3.3 0.65) (+ y ds 1.13) 0) (list (+ x 12.20 4 3.3 1.95) (- (+ y ds) 1.13) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 4 3.3 0.65) (- (+ y ds) 1.13) 0) (list (+ x 12.20 4 3.3 1.95) (+ y ds 1.13) 0) layer "Continuous" 1)
          (draw-circle (list (+ x 12.20 4 3.3 2.6 2) (+ y ds) 0) 2 layer)
          (draw-circle (list (+ x 12.20 4 3.3 2.6 2 2 1.3) (+ y ds) 0) 1.3 layer)
          (draw-line (list (+ x 12.20 4 3.3 0.65 6.61) (+ y ds 1.13) 0) (list (+ x 12.20 4 3.3 1.95 6.61) (- (+ y ds) 1.13) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 4 3.3 0.65 6.61) (- (+ y ds) 1.13) 0) (list (+ x 12.20 4 3.3 1.95 6.61) (+ y ds 1.13) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 12.20 4 3.3 2.6 2 2 1.3 1) (- (+ y ds) 3) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (+ x 12.20 2 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.96) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)

          (setq texte_pancarte_1
          (getstring T "\nEntrer le texte de la premiere pancarte  (\\ pour sauter une ligne) : "))

          (if (= texte_pancarte_1 "")
            (setq texte_pancarte_1 "-")
          )

          (setq texte_pancarte_2
          (getstring T "\nEntrer le texte de la deuxieme pancarte  (\\ pour sauter une ligne) : "))

          (if (= texte_pancarte_2 "")
            (setq texte_pancarte_2 "-")
          )

          (draw-mtext (list (- (+ x 12.20 2 0.48 2) 0.48 4) (+ y ds 1 0.96 3.36 1 1 1) 0) (strcat texte_pancarte_1 " // " texte_pancarte_2) layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (- (+ y ds) 1) 0) (list (+ x 12.20 2) (- (+ y ds) 1 2.50) 0) layer "Continuous" 1)

          (setq ds_p "")
          (setq ds_p (getstring "\nLa distance par rapport aux bords du quai ? (ex: 1.5) <...> : "))

          (if (= ds_p "")
            (setq ds_p "...")
          )

          (draw-cotlin-perso
                  (list (- (+ x 12.20 2.5) 14.20 0.5) (- (+ y ds) 1 1.25 2) 0)
                  (list (- (+ x 12.20 2.5) 0.5) (- (+ y ds) 1 1.25 2) 0)
                  (strcat ds_p "m")
                  layer
          )

          (draw-line (list (+ x 44.24) (- (+ y ds) 4.10) 0) (list (+ x 44.24 3.60) (- (+ y ds) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 1.43 0.16) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) (list (- (+ x 44.24 2.17) 0.16) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.59) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.59 0.42) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          ;;P1
          (draw-rect (list (+ x 37.85) (+ y ds 4.34) 0) (list (+ x 41.84) (+ y ds 0.30) 0) layer)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 1.01) 0) (list (+ x 41.84 3.93) (+ y ds 0.30 1.01) 0) layer "Continuous" 1)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 3.03) 0) (list (+ x 41.84 3.96) (+ y ds 0.30 3.03) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 39.84) (+ y ds 2.32) 0) texte_pancarte_1 layer 1 0 20)
          ;;P2
          (draw-rect (list (+ x 37.85) (- (+ y ds 4.34) 4.04) 0) (list (+ x 41.84) (- (+ y ds 0.30) 4.04) 0) layer)
          (draw-line (list (+ x 41.84) (- (+ y ds 0.30 1.01) 4.04) 0) (list (+ x 41.84 3.85) (- (+ y ds 0.30 1.01) 4.04) 0) layer "Continuous" 1)
          (draw-line (list (+ x 41.84) (- (+ y ds 0.30 3.03) 4.04) 0) (list (+ x 41.84 3.89) (- (+ y ds 0.30 3.03) 4.04) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 39.84) (- (+ y ds 2.32) 4.04) 0) texte_pancarte_2 layer 1 0 20)
        )
        ((= h_q "S")
          (draw-line-ep (list (+ x 12.20) (+ y ds) 0) (list (+ x 12.20 4) (+ y ds) 0) layer "Continuous" 1 0.60)
          (draw-line (list (+ x 12.20 4) (+ y ds) 0) (list (+ x 12.20 4 3.3) (+ y ds) 0) layer "Continuous" 1)
          (draw-rect (list (+ x 12.20 4 3.3) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (- (+ y ds) 1.5) 0) layer)
          (hatch-poly4-pattern (list (+ x 12.20 4 3.3) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (+ y ds 1.50) 0) (list (+ x 12.20 4 3.3 6) (- (+ y ds) 1.5) 0) (list (+ x 12.20 4 3.3) (- (+ y ds) 1.5) 0) layer 7 "ANSI31" 0.25)

          (draw-mtext (list (+ x 12.20 4 3.3 2.6 2 2 1.3 1) (- (+ y ds) 3) 0) (strcat (rtos ds 2 2) "m") layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (+ x 12.20 2) (+ y ds 1) 0) (list (+ x 12.20 2 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.96) 0.48) (+ y ds 1 0.96) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96) 0) (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)
          (draw-line (list (- (+ x 12.20 2 0.48) 0.48) (+ y ds 1 0.96 3.36) 0) (list (- (+ x 12.20 2 0.48) 0.48 4) (+ y ds 1 0.96 3.36) 0) layer "Continuous" 1)

          (setq texte_pancarte_1
          (getstring T "\nEntrer le texte de la premiere pancarte  (\\ pour sauter une ligne) : "))

          (if (= texte_pancarte_1 "")
            (setq texte_pancarte_1 "-")
          )

          (setq texte_pancarte_2
          (getstring T "\nEntrer le texte de la deuxieme pancarte  (\\ pour sauter une ligne) : "))

          (if (= texte_pancarte_2 "")
            (setq texte_pancarte_2 "-")
          )

          (draw-mtext (list (- (+ x 12.20 2 0.48 2) 0.48 4) (+ y ds 1 0.96 3.36 1 1 1) 0) (strcat texte_pancarte_1 " // " texte_pancarte_2) layer 2 0 20)

          (draw-line (list (+ x 12.20 2) (- (+ y ds) 1) 0) (list (+ x 12.20 2) (- (+ y ds) 1 2.50) 0) layer "Continuous" 1)

          (setq ds_p "")
          (setq ds_p (getstring "\nLa distance par rapport aux bords du quai ? (ex: 1.5) <...> : "))

          (if (= ds_p "")
            (setq ds_p "...")
          )

          (draw-cotlin-perso
                  (list (- (+ x 12.20 2.5) 14.20 0.5) (- (+ y ds) 1 1.25 2) 0)
                  (list (- (+ x 12.20 2.5) 0.5) (- (+ y ds) 1 1.25 2) 0)
                  (strcat ds_p "m")
                  layer
          )

          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 1.43) (- (+ y ds) 4.10) 0) (list (+ x 44.24 1.43) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-line (list (+ x 44.24 2.17) (- (+ y ds) 4.10) 0) (list (+ x 44.24 2.17) (- (+ y ds 9.10) 4.10) 0) layer "Continuous" 1)
          (draw-rect (list (- (+ x 44.24 1.43) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.43 2.37) (- (+ y ds 9.10 2) 4.10) 0) layer)
          (hatch-poly4-pattern (list (- (+ x 44.24 1.43) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (- (+ x 44.24 1.43 4) 1.63) (- (+ y ds 9.10) 4.10) 0) (list (+ x 44.24 1.43 2.37) (- (+ y ds 9.10 2) 4.10) 0) (list (- (+ x 44.24 1.43 2.37) 4) (- (+ y ds 9.10 2) 4.10) 0) layer 7 "ANSI31" 0.25)
          ;;P1
          (draw-rect (list (+ x 37.85) (+ y ds 4.34) 0) (list (+ x 41.84) (+ y ds 0.30) 0) layer)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 1.01) 0) (list (+ x 41.84 3.83) (+ y ds 0.30 1.01) 0) layer "Continuous" 1)
          (draw-line (list (+ x 41.84) (+ y ds 0.30 3.03) 0) (list (+ x 41.84 3.83) (+ y ds 0.30 3.03) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 39.84) (+ y ds 2.32) 0) texte_pancarte layer 1 0 20)
          ;;P2
          (draw-rect (list (+ x 37.85) (- (+ y ds 4.34) 4.04) 0) (list (+ x 41.84) (- (+ y ds 0.30) 4.04) 0) layer)
          (draw-line (list (+ x 41.84) (- (+ y ds 0.30 1.01) 4.04) 0) (list (+ x 41.84 3.83) (- (+ y ds 0.30 1.01) 4.04) 0) layer "Continuous" 1)
          (draw-line (list (+ x 41.84) (- (+ y ds 0.30 3.03) 4.04) 0) (list (+ x 41.84 3.83) (- (+ y ds 0.30 3.03) 4.04) 0) layer "Continuous" 1)

          (draw-mtext (list (+ x 39.84) (- (+ y ds 2.32) 4.04) 0) texte_pancarte_2 layer 1 0 20)
        )
      )
    )
    
  )
)

(defun draw-catenaire-h (pt t2 ds layer / x y c numero_cat)
  (setq x (car pt))
  (setq y (cadr pt))

  (draw-line-ep (list (+ x 55.94) (+ y ds) 0) (list (+ x 55.94 4) (+ y ds) 0) layer "Continuous" 1 0.60)
  (draw-line-ep (list (+ x 55.94) (- (+ y ds) 2) 0) (list (+ x 55.94) (+ y ds 2) 0) layer "Continuous" 1 0.60)
  (draw-line-ep (list (+ x 55.94 4) (- (+ y ds) 2) 0) (list (+ x 55.94 4) (+ y ds 2) 0) layer "Continuous" 1 0.60)

  (setq numero_cat
  (getstring T "\nEntrer le numéro de la catenaire (ex. 88 / 09) : "))  
  (if (= numero_cat "")
    (setq numero_cat "? / ?")
  )

  (draw-mtext (list (+ x 55.94 2) (+ y ds 5.5) 0) "CAT" layer 3 0 13)
  (draw-mtext (list (+ x 55.94 2) (- (+ y ds) 5.5) 0) numero_cat layer 3 0 13)
  (draw-mtext (list (+ x 55.94 2 4 7) (+ y ds) 0) (strcat (rtos ds 2 2) " m") layer 3 0 13)
)


(defun menu-ajout-equipements-h (pt t2 / choix ds_eq)
  (setq choix "")

  (while (/= choix "Q")
    (initget "P C A N O Q")
    (setq choix
      (getkword
        "\nAjouter un equipement ? [Pancarte/Camera/cAtenaire/aNtenne/crOcodile/Quitter] <Q> : "
      )
    )

    ;; Si Entrée, on quitte
    (if (null choix)
      (setq choix "Q")
    )

    (cond
      ;; Pancarte de signalisation
      ((= choix "P")
        (setq ds_eq (getreal "\nLa distance où se trouve la pancarte à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-pancarte-h pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ;; Camera
      ((= choix "C")
        (setq ds_eq (getreal "\nLa distance où se trouve la caméra à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-camera-h pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ;; Catenaire
      ((= choix "A")
        (setq ds_eq (getreal "\nLa distance où se trouve la catenaire à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-catenaire-h pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ;; Catenaire
      ((= choix "N")
        (setq ds_eq (getreal "\nLa distance où se trouve l'antenne à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-antenne pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ((= choix "O")
        (setq ds_eq (getreal "\nLa distance où se trouve le crocodile à partir du début du quai (0 m) : "))
        (if ds_eq
          (progn
            (if (>= ds_eq 0)
              (progn
                (draw-crocodile pt t2 ds_eq "0")
              )
              (progn
                (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
              )
            )
          )
          (progn
            (princ "\nErreur : Aucun distance donnée.")
          )
        )
      )

      ;; Quitter
      ((= choix "Q")
        (princ "\nFin de l'ajout des equipements.")
      )
    )
  )
)


(defun draw-quai-h (pt layer longueur t1 / x y dp heurtoir)
  (setq x (car pt))
  (setq y (cadr pt))

  (draw-line (list (+ x t1) y 0) (list x y 0) layer "ISO07W100" 0.25)

  (setq dp (getreal "\nEntrer la distance de depart <0> : "))

  (if (null dp)
    (setq dp 0)
  )

  (if (>= dp 0)
    (progn
      (draw-mtext (list (+ x t1 5) (+ y) 0) (strcat "BQ:\\P" (rtos dp 2 2) " m") "0" 1.5 0 20)
    )
    (progn
      (princ "\nErreur : la distance doit etre superieure ou egale a 0.")
      (exit)
    )
  )

  (draw-line (list (+ x) y 0) (list (+ x) (+ y longueur) 0) layer "Continuous" 1)

  (initget "O N")
    (setq heurtoir (getkword "\nY a-t-il un heurtoir au bout du quai ? [Oui/Non] <N> : "))

    (if (= heurtoir "O")
      (progn
        (draw-line (list (+ x) (+ y longueur) 0) (list (- x 7) (+ y longueur) 0) layer "Continuous" 1)
        (draw-line (list (- x 7) (+ y longueur) 0) (list (- x 7) (+ y longueur 2) 0) layer "Continuous" 1)
        (draw-line (list (- x 7) (+ y longueur 2) 0) (list (+ x) (+ y longueur 2) 0) layer "Continuous" 1)

        (draw-line (list (- x 3.5) (- (+ y longueur) 1) 0) (list (- x 3.5) (+ y longueur) 0) layer "Continuous" 1)
        (draw-line (list (- x 3.5) (- (+ y longueur) 1) 0) (list (- x 3.5 2) (- (+ y longueur) 1) 0) layer "Continuous" 1)
        (draw-line (list (- x 3.5 2) (- (+ y longueur) 1) 0) (list (- x 3.5 2) (- (+ y longueur 1) 1) 0) layer "Continuous" 1)
      )
    )

  ;; VOIE
  (draw-line (list (- x 8.5) y 0) (list (- x 8.5) (- (+ y longueur) 1) 0) layer "Continuous" 1)
  (draw-line (list (- x 8.5 7) y 0) (list (- x 8.5 7) (- (+ y longueur) 1) 0) layer "Continuous" 1)

  (setq ds 4.8) ;; Premiere traverse

  (while (<= ds longueur)
    (draw-line (list (- x 6) (+ y ds) 0) (list (- x 18) (+ y ds) 0) layer "Continuous" 1)
    (setq ds (+ ds 4.8))
  )

)

(defun c:S_QUAI_HAUT (/ longueur pt x y heurtoir heurtoir_pt texte_pt)
  (make-layer "TL_MATERIEL_EXISTANT" 7)
  (make-layer "TL_MATERIEL_POSE" 12)
  (make-layer "TL_MATERIEL_REPOSE" 94)
  (make-layer "TL_MATERIEL_DEPOSE" 40)

  (setq longueur (getreal "\nEntrer la longueur du quai en metres : "))

  (if (and longueur (> longueur 0))
    (progn
      (setq pt (getpoint "\nCliquer le point de depart du quai : "))

      ;; Hauteurs graphiques des bandes

      (draw-quai-h pt "0" longueur 6)
      (princ "\nQuai cree avec succès")

      (menu-ajout-equipements-h pt 0)
      
    )
    (princ "\nErreur : la longueur doit etre superieure a 0.")
  )

  (princ)
)

;; ------------------------------------------------------------------------------------ C_S_TABLEAU ------------------------------------------------------------------------------------

(vl-load-com)

(setq STAB_APP "S_TABLEAU_CALQUES")
(setq STAB_PREFIX "S_TAB_CALQUES_")
(setq *STAB_REACTOR* nil)
(setq *STAB_BUSY* nil)

(defun stab_regapp ()
  (if (not (tblsearch "APPID" STAB_APP))
    (regapp STAB_APP)
  )
)

(defun stab_uuid (/ s)
  (setq s (rtos (getvar "CDATE") 2 8))
  (setq s (vl-string-subst "" "." s))
  (strcat STAB_PREFIX s)
)

(defun stab_split (str sep / pos out)
  (setq out '())
  (while (setq pos (vl-string-search sep str))
    (setq out (cons (substr str 1 pos) out))
    (setq str (substr str (+ pos 2)))
  )
  (reverse (cons str out))
)

(defun stab_join_row (row)
  (strcat
    (nth 0 row) "|"
    (nth 1 row) "|"
    (nth 2 row) "|"
    (if (nth 3 row) (nth 3 row) "1.0") "|"
    (if (nth 4 row) (nth 4 row) "") "|"
    (if (nth 5 row) (nth 5 row) "0")
  )
)

(defun stab_parse_row (s / p)
  (setq p (stab_split s "|"))
  (cond
    ((= (length p) 6) p)
    ((= (length p) 5) (append p (list "0")))
    ((= (length p) 4) (append p (list "" "0")))
    ((= (length p) 3) (append p (list "1.0" "" "0")))
    (T nil)
  )
)

(defun stab_set_rows (ent rows / ed xdata)
  (stab_regapp)
  (setq ed (entget ent))
  (setq ed
    (vl-remove-if
      '(lambda (x) (= (car x) -3))
      ed
    )
  )
  (setq xdata
    (list
      (list -3
        (cons STAB_APP
          (mapcar
            '(lambda (r) (cons 1000 (stab_join_row r)))
            rows
          )
        )
      )
    )
  )
  (entmod (append ed xdata))
  (entupd ent)
)

(defun stab_get_rows (ent / ed x app data rows)
  (setq ed (entget ent (list STAB_APP)))
  (setq x (assoc -3 ed))
  (if x
    (progn
      (setq app (assoc STAB_APP (cdr x)))
      (if app
        (progn
          (setq data (cdr app))
          (setq rows
            (vl-remove nil
              (mapcar
                '(lambda (d)
                  (if (= (car d) 1000)
                    (stab_parse_row (cdr d))
                  )
                )
                data
              )
            )
          )
          rows
        )
      )
    )
  )
)

(defun stab_is_table (ent)
  (and
    ent
    (= (cdr (assoc 0 (entget ent))) "INSERT")
    (stab_get_rows ent)
  )
)

(defun stab_layer_list (/ d r)
  (setq r '())
  (setq d (tblnext "LAYER" T))
  (while d
    (setq r (cons (cdr (assoc 2 d)) r))
    (setq d (tblnext "LAYER"))
  )
  (acad_strlsort (reverse r))
)

(defun stab_index_of (val lst / i)
  (setq i 0)
  (while (and lst (/= (strcase val) (strcase (car lst))))
    (setq i (1+ i))
    (setq lst (cdr lst))
  )
  (if lst i 0)
)

(defun stab_layer_color_data (lay / d c)
  (setq d (tblsearch "LAYER" lay))
  (cond
    ((and d (assoc 420 d))
      (list (assoc 420 d))
    )
    ((and d (assoc 62 d))
      (setq c (abs (cdr (assoc 62 d))))
      (if (= c 0) (setq c 7))
      (list (cons 62 c))
    )
    (T
      (list (cons 62 7))
    )
  )
)

(defun stab_write_dcl_main (/ fn f)
  (setq fn (vl-filename-mktemp "stab_tableau_main.dcl"))
  (setq f (open fn "w"))

  (write-line
"stab_main : dialog {
  label = \"SNCF - Tableau calques\";

  : boxed_column {
    label = \"Action\";

    : button {
      key = \"creer\";
      label = \"Creer un nouveau tableau\";
      width = 45;
      is_default = true;
    }

    : button {
      key = \"ajouter\";
      label = \"Ajouter une ligne\";
      width = 45;
    }

    : button {
      key = \"modifier\";
      label = \"Modifier une ligne\";
      width = 45;
    }

    : button {
      key = \"supprimer\";
      label = \"Supprimer une ligne\";
      width = 45;
    }

    : button {
      key = \"maj\";
      label = \"Mettre a jour tous les tableaux\";
      width = 45;
    }
  }

  spacer;

  cancel_button;
}"
    f
  )

  (close f)
  fn
)

(defun stab_main_dialog (/ fn id res)
  (setq fn (stab_write_dcl_main))
  (setq id (load_dialog fn))

  (if (not (new_dialog "stab_main" id))
    (progn
      (unload_dialog id)
      (vl-file-delete fn)
      nil
    )
    (progn
      (action_tile "creer" "(setq res \"CREER\") (done_dialog 1)")
      (action_tile "ajouter" "(setq res \"AJOUTER\") (done_dialog 1)")
      (action_tile "modifier" "(setq res \"MODIFIER\") (done_dialog 1)")
      (action_tile "supprimer" "(setq res \"SUPPRIMER\") (done_dialog 1)")
      (action_tile "maj" "(setq res \"MAJ\") (done_dialog 1)")
      (action_tile "cancel" "(setq res nil) (done_dialog 0)")

      (start_dialog)

      (unload_dialog id)
      (vl-file-delete fn)
      res
    )
  )
)

(defun stab_write_dcl_row (title / fn f)
  (setq fn (vl-filename-mktemp "stab_tableau_row.dcl"))
  (setq f (open fn "w"))

  (write-line
    (strcat
"stab_row : dialog {
  label = \"" title "\";

  : boxed_column {
    label = \"Parametres de la ligne\";

    : edit_box {
      label = \"Nom dans le tableau :\";
      key = \"lib\";
      edit_width = 42;
    }

    : popup_list {
      label = \"Calque a calculer :\";
      key = \"calque\";
      width = 48;
    }

    : popup_list {
      label = \"Type de calcul :\";
      key = \"type\";
      width = 48;
    }

    : edit_box {
      label = \"Multiplicateur :\";
      key = \"coef\";
      edit_width = 12;
      value = \"1.0\";
    }

    : edit_box {
      label = \"Prix unitaire, optionnel :\";
      key = \"prix\";
      edit_width = 12;
      value = \"\";
    }

    : edit_box {
      label = \"Marge en %, optionnel, exemple +20 ou -20 :\";
      key = \"marge\";
      edit_width = 12;
      value = \"0\";
    }

    : text {
      label = \"Pour m3 : volume = surface du calque x multiplicateur.\";
    }
  }

  spacer;
  ok_cancel;
}"
    )
    f
  )

  (close f)
  fn
)

(defun stab_row_dialog (defaultRow title / fn id layers types cur li ti lab coef prix marge res modeIndex)
  (setq layers (stab_layer_list))
  (setq types
    '(
      "Nombre d'elements"
      "ML - metre lineaire"
      "M2 - surface"
      "M3 - m2 x multiplicateur"
    )
  )

  (setq fn (stab_write_dcl_row title))
  (setq id (load_dialog fn))

  (if (not (new_dialog "stab_row" id))
    (progn
      (unload_dialog id)
      (vl-file-delete fn)
      nil
    )
    (progn
      (start_list "calque")
      (mapcar 'add_list layers)
      (end_list)

      (start_list "type")
      (mapcar 'add_list types)
      (end_list)

      (if defaultRow
        (progn
          (setq lab (nth 0 defaultRow))
          (setq li (stab_index_of (nth 1 defaultRow) layers))
          (setq coef (if (nth 3 defaultRow) (nth 3 defaultRow) "1.0"))
          (setq prix (if (nth 4 defaultRow) (nth 4 defaultRow) ""))
          (setq marge (if (nth 5 defaultRow) (nth 5 defaultRow) "0"))

          (setq modeIndex
            (cond
              ((= (nth 2 defaultRow) "NB") 0)
              ((= (nth 2 defaultRow) "ML") 1)
              ((= (nth 2 defaultRow) "M2") 2)
              ((= (nth 2 defaultRow) "M3") 3)
              (T 0)
            )
          )

          (set_tile "lib" lab)
          (set_tile "calque" (itoa li))
          (set_tile "type" (itoa modeIndex))
          (set_tile "coef" coef)
          (set_tile "prix" prix)
          (set_tile "marge" marge)
        )
        (progn
          (setq cur (getvar "CLAYER"))
          (set_tile "calque" (itoa (stab_index_of cur layers)))
          (set_tile "type" "0")
          (set_tile "lib" cur)
          (set_tile "coef" "1.0")
          (set_tile "prix" "")
          (set_tile "marge" "0")
        )
      )

      (action_tile "accept"
        "(setq lab (get_tile \"lib\"))
         (setq li (atoi (get_tile \"calque\")))
         (setq ti (atoi (get_tile \"type\")))
         (setq coef (get_tile \"coef\"))
         (setq prix (get_tile \"prix\"))
         (setq marge (get_tile \"marge\"))
         (done_dialog 1)"
      )

      (action_tile "cancel" "(done_dialog 0)")

      (if (= (start_dialog) 1)
        (progn
          (if (= lab "") (setq lab (nth li layers)))

          (if (= coef "") (setq coef "1.0"))
          (if (not (distof coef 2)) (setq coef "1.0"))

          (if (/= prix "")
            (if (not (distof prix 2))
              (setq prix "")
            )
          )

          (if (= marge "") (setq marge "0"))
          (if (not (distof marge 2)) (setq marge "0"))

          (setq res
            (list
              lab
              (nth li layers)
              (nth ti '("NB" "ML" "M2" "M3"))
              coef
              prix
              marge
            )
          )
        )
        (setq res nil)
      )

      (unload_dialog id)
      (vl-file-delete fn)
      res
    )
  )
)

(defun stab_write_dcl_select_line (title / fn f)
  (setq fn (vl-filename-mktemp "stab_tableau_select.dcl"))
  (setq f (open fn "w"))

  (write-line
    (strcat
"stab_select : dialog {
  label = \"" title "\";

  : boxed_column {
    label = \"Ligne\";

    : popup_list {
      key = \"ligne\";
      width = 115;
    }
  }

  spacer;
  ok_cancel;
}"
    )
    f
  )

  (close f)
  fn
)

(defun stab_unit (mode)
  (cond
    ((= mode "NB") "u")
    ((= mode "ML") "ml")
    ((= mode "M2") "m2")
    ((= mode "M3") "m3")
    (T "")
  )
)

(defun stab_select_line_dialog (rows title / fn id i labels idx res prixTxt margeTxt)
  (setq labels '())
  (setq i 1)

  (foreach r rows
    (setq prixTxt
      (if (and (nth 4 r) (/= (nth 4 r) ""))
        (strcat " | PU " (nth 4 r))
        ""
      )
    )

    (setq margeTxt
      (if (and (nth 5 r) (/= (nth 5 r) "") (/= (nth 5 r) "0"))
        (strcat " | marge " (nth 5 r) "%")
        ""
      )
    )

    (setq labels
      (append labels
        (list
          (strcat
            (itoa i)
            " - "
            (nth 0 r)
            " | "
            (nth 1 r)
            " | "
            (stab_unit (nth 2 r))
            (if (= (nth 2 r) "M3")
              (strcat " | x" (nth 3 r))
              ""
            )
            prixTxt
            margeTxt
          )
        )
      )
    )
    (setq i (1+ i))
  )

  (setq fn (stab_write_dcl_select_line title))
  (setq id (load_dialog fn))

  (if (not (new_dialog "stab_select" id))
    (progn
      (unload_dialog id)
      (vl-file-delete fn)
      nil
    )
    (progn
      (start_list "ligne")
      (mapcar 'add_list labels)
      (end_list)

      (set_tile "ligne" "0")

      (action_tile "accept"
        "(setq idx (atoi (get_tile \"ligne\")))
         (done_dialog 1)"
      )

      (action_tile "cancel" "(done_dialog 0)")

      (if (= (start_dialog) 1)
        (setq res idx)
        (setq res nil)
      )

      (unload_dialog id)
      (vl-file-delete fn)
      res
    )
  )
)

(defun stab_replace_nth (n new lst / i out)
  (setq i 0)
  (setq out '())
  (foreach x lst
    (if (= i n)
      (setq out (cons new out))
      (setq out (cons x out))
    )
    (setq i (1+ i))
  )
  (reverse out)
)

(defun stab_remove_nth (n lst / i out)
  (setq i 0)
  (setq out '())
  (foreach x lst
    (if (/= i n)
      (setq out (cons x out))
    )
    (setq i (1+ i))
  )
  (reverse out)
)

(defun stab_curve_length (ent / r)
  (setq r
    (vl-catch-all-apply
      '(lambda ()
        (vlax-curve-getDistAtParam ent (vlax-curve-getEndParam ent))
      )
    )
  )
  (if (vl-catch-all-error-p r)
    0.0
    r
  )
)

(defun stab_obj_area (ent / obj r)
  (setq obj (vlax-ename->vla-object ent))
  (setq r
    (vl-catch-all-apply
      '(lambda ()
        (if (vlax-property-available-p obj 'Area)
          (vla-get-Area obj)
          0.0
        )
      )
    )
  )
  (if (vl-catch-all-error-p r)
    0.0
    r
  )
)

(defun stab_count_layer (lay / ss i ent n)
  (setq n 0)
  (setq ss (ssget "_X" (list (cons 8 lay))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if (not (stab_is_table ent))
          (setq n (1+ n))
        )
        (setq i (1+ i))
      )
    )
  )
  n
)

(defun stab_sum_ml (lay / ss i ent sum)
  (setq sum 0.0)
  (setq ss (ssget "_X" (list (cons 8 lay))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if (not (stab_is_table ent))
          (setq sum (+ sum (stab_curve_length ent)))
        )
        (setq i (1+ i))
      )
    )
  )
  sum
)

(defun stab_sum_m2 (lay / ss i ent sum)
  (setq sum 0.0)
  (setq ss (ssget "_X" (list (cons 8 lay))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if (not (stab_is_table ent))
          (setq sum (+ sum (stab_obj_area ent)))
        )
        (setq i (1+ i))
      )
    )
  )
  sum
)

(defun stab_calc (lay mode coef / m2 c)
  (setq c (distof coef 2))
  (if (not c) (setq c 1.0))

  (cond
    ((= mode "NB") (stab_count_layer lay))
    ((= mode "ML") (stab_sum_ml lay))
    ((= mode "M2") (stab_sum_m2 lay))
    ((= mode "M3")
      (setq m2 (stab_sum_m2 lay))
      (* m2 c)
    )
    (T 0)
  )
)

(defun stab_margin_factor (marge / m)
  (setq m (distof marge 2))
  (if (not m) (setq m 0.0))
  (+ 1.0 (/ m 100.0))
)

(defun stab_calc_margin_qty (qty marge)
  (* qty (stab_margin_factor marge))
)

(defun stab_format_value (val mode)
  (if (= mode "NB")
    (itoa (fix val))
    (rtos val 2 2)
  )
)

(defun stab_format_margin_value (val mode)
  (rtos val 2 2)
)

(defun stab_format_price (prix)
  (if (and prix (/= prix "") (distof prix 2))
    (rtos (distof prix 2) 2 2)
    "-"
  )
)

(defun stab_total_price (val prix / p)
  (if (and prix (/= prix "") (distof prix 2))
    (progn
      (setq p (distof prix 2))
      (rtos (* val p) 2 2)
    )
    "-"
  )
)

(defun stab_visual_strlen (s / i c n)
  (setq n 0.0)
  (if (not s) (setq s ""))
  (setq i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (cond
      ((wcmatch c "[WM@#%&]") (setq n (+ n 1.35)))
      ((wcmatch c "[ABCDEFGHIJKLMNOPQRSTUVWXYZ]") (setq n (+ n 1.15)))
      ((wcmatch c "[ijlI.,:;!|]") (setq n (+ n 0.45)))
      ((wcmatch c "[ _-]") (setq n (+ n 0.75)))
      (T (setq n (+ n 1.00)))
    )
    (setq i (1+ i))
  )
  n
)

(defun stab_max_real (lst / m)
  (setq m 0.0)
  (foreach x lst
    (if (> x m)
      (setq m x)
    )
  )
  m
)

(defun stab_col_width_from_strings (strings minW charW padding / maxLen)
  (setq maxLen (stab_max_real (mapcar 'stab_visual_strlen strings)))
  (max minW (+ padding (* maxLen charW)))
)

(defun stab_text_ent (pt h txt colorData / data)
  (setq data
    (list
      '(0 . "TEXT")
      '(8 . "0")
      (cons 10 pt)
      (cons 11 pt)
      (cons 40 h)
      (cons 1 txt)
      '(7 . "STANDARD")
      '(72 . 0)
      '(73 . 2)
    )
  )
  (if colorData
    (setq data (append data colorData))
  )
  (entmake data)
)

(defun stab_text_cell (xL xR y h txt colorData / margin avail need p1 p2 data)
  (if (not txt) (setq txt ""))
  (setq margin 0.10)
  (setq avail (- (- xR xL) (* 2.0 margin)))
  (if (< avail 0.05) (setq avail 0.05))
  (setq need (* (stab_visual_strlen txt) h 0.72))

  (if (> need avail)
    (progn
      (setq p1 (list (+ xL margin) y 0.0))
      (setq p2 (list (- xR margin) y 0.0))
      (setq data
        (list
          '(0 . "TEXT")
          '(8 . "0")
          (cons 10 p1)
          (cons 11 p2)
          (cons 40 h)
          (cons 1 txt)
          '(7 . "STANDARD")
          '(72 . 5)
          '(73 . 2)
        )
      )
      (if colorData
        (setq data (append data colorData))
      )
      (entmake data)
    )
    (stab_text_ent
      (list (+ xL margin) y 0.0)
      h
      txt
      colorData
    )
  )
)

(defun stab_line (p1 p2)
  (entmake
    (list
      '(0 . "LINE")
      '(8 . "0")
      (cons 10 p1)
      (cons 11 p2)
    )
  )
)

(defun stab_delete_block_def (bname / doc blocks blk r)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq blocks (vla-get-Blocks doc))
  (setq r
    (vl-catch-all-apply
      '(lambda ()
        (setq blk (vla-item blocks bname))
        (vla-delete blk)
      )
    )
  )
  r
)

(defun stab_make_block_def
  (
    bname rows /
    h rh th n y
    w1 w2 w3 w4 w5 w6 w7 w8 w9 w10
    x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11
    row val valM mode lay lib unit coef coefTxt layColor prix marge puTxt ptTxt ptMargeTxt margeTxt
    col1 col2 col3 col4 col5 col6 col7 col8 col9 col10
    charW padding
  )

  (setq rh 0.55)
  (setq th 0.16)
  (setq charW 0.125)
  (setq padding 0.55)
  (setq n (+ 1 (length rows)))
  (setq h (* rh n))

  (setq col1 (list "Designation"))
  (setq col2 (list "Calque"))
  (setq col3 (list "Type"))
  (setq col4 (list "Coef."))
  (setq col5 (list "Quantite"))
  (setq col6 (list "Marge"))
  (setq col7 (list "Qte marge"))
  (setq col8 (list "Prix U."))
  (setq col9 (list "Prix T."))
  (setq col10 (list "Prix T. marge"))

  (foreach row rows
    (setq lib (nth 0 row))
    (setq lay (nth 1 row))
    (setq mode (nth 2 row))
    (setq coef (if (nth 3 row) (nth 3 row) "1.0"))
    (setq prix (if (nth 4 row) (nth 4 row) ""))
    (setq marge (if (nth 5 row) (nth 5 row) "0"))

    (setq val (stab_calc lay mode coef))
    (setq valM (stab_calc_margin_qty val marge))
    (setq unit (stab_unit mode))

    (if (= mode "M3")
      (setq coefTxt coef)
      (setq coefTxt "-")
    )

    (setq margeTxt
      (if (and marge (/= marge ""))
        (strcat marge "%")
        "0%"
      )
    )

    (setq puTxt (stab_format_price prix))
    (setq ptTxt (stab_total_price val prix))
    (setq ptMargeTxt (stab_total_price valM prix))

    (setq col1 (cons lib col1))
    (setq col2 (cons lay col2))
    (setq col3 (cons unit col3))
    (setq col4 (cons coefTxt col4))
    (setq col5 (cons (stab_format_value val mode) col5))
    (setq col6 (cons margeTxt col6))
    (setq col7 (cons (stab_format_margin_value valM mode) col7))
    (setq col8 (cons puTxt col8))
    (setq col9 (cons ptTxt col9))
    (setq col10 (cons ptMargeTxt col10))
  )

  (setq w1  (stab_col_width_from_strings col1  3.00 charW padding))
  (setq w2  (stab_col_width_from_strings col2  3.00 charW padding))
  (setq w3  (stab_col_width_from_strings col3  1.20 charW padding))
  (setq w4  (stab_col_width_from_strings col4  1.30 charW padding))
  (setq w5  (stab_col_width_from_strings col5  1.90 charW padding))
  (setq w6  (stab_col_width_from_strings col6  1.50 charW padding))
  (setq w7  (stab_col_width_from_strings col7  2.10 charW padding))
  (setq w8  (stab_col_width_from_strings col8  1.80 charW padding))
  (setq w9  (stab_col_width_from_strings col9  1.80 charW padding))
  (setq w10 (stab_col_width_from_strings col10 2.60 charW padding))

  (setq x1 0.0)
  (setq x2 (+ x1 w1))
  (setq x3 (+ x2 w2))
  (setq x4 (+ x3 w3))
  (setq x5 (+ x4 w4))
  (setq x6 (+ x5 w5))
  (setq x7 (+ x6 w6))
  (setq x8 (+ x7 w7))
  (setq x9 (+ x8 w8))
  (setq x10 (+ x9 w9))
  (setq x11 (+ x10 w10))

  (entmake
    (list
      '(0 . "BLOCK")
      (cons 2 bname)
      '(70 . 0)
      '(10 0.0 0.0 0.0)
    )
  )

  (stab_line (list x1 0.0 0.0) (list x11 0.0 0.0))
  (stab_line (list x1 (- h) 0.0) (list x11 (- h) 0.0))

  (foreach x (list x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11)
    (stab_line (list x 0.0 0.0) (list x (- h) 0.0))
  )

  (setq y (- rh))
  (stab_line (list x1 y 0.0) (list x11 y 0.0))

  (stab_text_cell x1  x2  (- (/ rh 2.0)) th "Designation" nil)
  (stab_text_cell x2  x3  (- (/ rh 2.0)) th "Calque" nil)
  (stab_text_cell x3  x4  (- (/ rh 2.0)) th "Type" nil)
  (stab_text_cell x4  x5  (- (/ rh 2.0)) th "Coef." nil)
  (stab_text_cell x5  x6  (- (/ rh 2.0)) th "Quantite" nil)
  (stab_text_cell x6  x7  (- (/ rh 2.0)) th "Marge" nil)
  (stab_text_cell x7  x8  (- (/ rh 2.0)) th "Qte marge" nil)
  (stab_text_cell x8  x9  (- (/ rh 2.0)) th "Prix U." nil)
  (stab_text_cell x9  x10 (- (/ rh 2.0)) th "Prix T." nil)
  (stab_text_cell x10 x11 (- (/ rh 2.0)) th "Prix T. marge" nil)

  (foreach row rows
    (setq lib (nth 0 row))
    (setq lay (nth 1 row))
    (setq mode (nth 2 row))
    (setq coef (if (nth 3 row) (nth 3 row) "1.0"))
    (setq prix (if (nth 4 row) (nth 4 row) ""))
    (setq marge (if (nth 5 row) (nth 5 row) "0"))

    (setq val (stab_calc lay mode coef))
    (setq valM (stab_calc_margin_qty val marge))
    (setq unit (stab_unit mode))
    (setq layColor (stab_layer_color_data lay))

    (if (= mode "M3")
      (setq coefTxt coef)
      (setq coefTxt "-")
    )

    (setq margeTxt
      (if (and marge (/= marge ""))
        (strcat marge "%")
        "0%"
      )
    )

    (setq puTxt (stab_format_price prix))
    (setq ptTxt (stab_total_price val prix))
    (setq ptMargeTxt (stab_total_price valM prix))

    (setq y (- y rh))
    (stab_line (list x1 y 0.0) (list x11 y 0.0))

    (stab_text_cell x1  x2  (+ y (/ rh 2.0)) th lib nil)
    (stab_text_cell x2  x3  (+ y (/ rh 2.0)) th lay layColor)
    (stab_text_cell x3  x4  (+ y (/ rh 2.0)) th unit nil)
    (stab_text_cell x4  x5  (+ y (/ rh 2.0)) th coefTxt nil)
    (stab_text_cell x5  x6  (+ y (/ rh 2.0)) th (stab_format_value val mode) nil)
    (stab_text_cell x6  x7  (+ y (/ rh 2.0)) th margeTxt nil)
    (stab_text_cell x7  x8  (+ y (/ rh 2.0)) th (stab_format_margin_value valM mode) nil)
    (stab_text_cell x8  x9  (+ y (/ rh 2.0)) th puTxt nil)
    (stab_text_cell x9  x10 (+ y (/ rh 2.0)) th ptTxt nil)
    (stab_text_cell x10 x11 (+ y (/ rh 2.0)) th ptMargeTxt nil)
  )

  (entmake '((0 . "ENDBLK")))
)

(defun stab_insert_table_ex (pt bname rows sx sy sz rot lay / ent)
  (if (not sx) (setq sx 1.0))
  (if (not sy) (setq sy 1.0))
  (if (not sz) (setq sz 1.0))
  (if (not rot) (setq rot 0.0))
  (if (not lay) (setq lay "0"))

  (entmake
    (list
      '(0 . "INSERT")
      (cons 2 bname)
      (cons 10 pt)
      (cons 41 sx)
      (cons 42 sy)
      (cons 43 sz)
      (cons 50 rot)
      (cons 8 lay)
    )
  )

  (setq ent (entlast))
  (stab_set_rows ent rows)
  ent
)

(defun stab_insert_table (pt bname rows)
  (stab_insert_table_ex pt bname rows 1.0 1.0 1.0 0.0 "0")
)

(defun stab_refresh_table (ent / ed pt bname rows newent sx sy sz rot lay)
  (if (stab_is_table ent)
    (progn
      (setq ed (entget ent))

      (setq pt (cdr (assoc 10 ed)))
      (setq bname (cdr (assoc 2 ed)))
      (setq rows (stab_get_rows ent))

      (setq sx (cdr (assoc 41 ed)))
      (setq sy (cdr (assoc 42 ed)))
      (setq sz (cdr (assoc 43 ed)))
      (setq rot (cdr (assoc 50 ed)))
      (setq lay (cdr (assoc 8 ed)))

      (if (not sx) (setq sx 1.0))
      (if (not sy) (setq sy 1.0))
      (if (not sz) (setq sz 1.0))
      (if (not rot) (setq rot 0.0))
      (if (not lay) (setq lay "0"))

      (entdel ent)
      (stab_delete_block_def bname)
      (stab_make_block_def bname rows)

      (setq newent
        (stab_insert_table_ex pt bname rows sx sy sz rot lay)
      )

      newent
    )
  )
)

(defun stab_refresh_all (/ ss i ent)
  (if (not *STAB_BUSY*)
    (progn
      (setq *STAB_BUSY* T)
      (setq ss (ssget "_X" '((0 . "INSERT"))))

      (if ss
        (progn
          (setq i 0)
          (while (< i (sslength ss))
            (setq ent (ssname ss i))
            (if (stab_is_table ent)
              (stab_refresh_table ent)
            )
            (setq i (1+ i))
          )
        )
      )

      (setq *STAB_BUSY* nil)
    )
  )
  (princ)
)

(defun stab_cmd_reactor (reactor params / cmd)
  (setq cmd (strcase (car params)))

  (if
    (and
      (not *STAB_BUSY*)
      (/= cmd "S_TABLEAU")
    )
    (stab_refresh_all)
  )
)

(defun stab_start_reactor ()
  (if (not *STAB_REACTOR*)
    (setq *STAB_REACTOR*
      (vlr-command-reactor
        nil
        '((:vlr-commandEnded . stab_cmd_reactor))
      )
    )
  )
)

(defun stab_pick_table (/ ent)
  (setq ent (car (entsel "\nSelectionne le bloc tableau : ")))
  (cond
    ((not ent)
      (princ "\nAucun tableau selectionne.")
      nil
    )
    ((not (stab_is_table ent))
      (princ "\nCe bloc n'est pas un tableau cree par ce script.")
      nil
    )
    (T ent)
  )
)

(defun stab_action_creer (/ row pt bname)
  (setq row (stab_row_dialog nil "SNCF - Creer un tableau"))

  (if row
    (progn
      (setq pt (getpoint "\nPoint d'insertion du tableau : "))
      (if pt
        (progn
          (setq bname (stab_uuid))
          (stab_make_block_def bname (list row))
          (stab_insert_table pt bname (list row))
          (princ "\nTableau cree.")
        )
      )
    )
  )
)

(defun stab_action_ajouter (/ ent row rows)
  (setq ent (stab_pick_table))

  (if ent
    (progn
      (setq row (stab_row_dialog nil "SNCF - Ajouter une ligne"))

      (if row
        (progn
          (setq rows (append (stab_get_rows ent) (list row)))
          (stab_set_rows ent rows)
          (stab_refresh_table ent)
          (princ "\nLigne ajoutee au tableau.")
        )
      )
    )
  )
)

(defun stab_action_modifier (/ ent rows idx oldRow newRow newRows)
  (setq ent (stab_pick_table))

  (if ent
    (progn
      (setq rows (stab_get_rows ent))
      (setq idx (stab_select_line_dialog rows "Modifier une ligne du tableau"))

      (if idx
        (progn
          (setq oldRow (nth idx rows))
          (setq newRow (stab_row_dialog oldRow "SNCF - Modifier la ligne"))

          (if newRow
            (progn
              (setq newRows (stab_replace_nth idx newRow rows))
              (stab_set_rows ent newRows)
              (stab_refresh_table ent)
              (princ "\nLigne modifiee.")
            )
          )
        )
      )
    )
  )
)

(defun stab_action_supprimer (/ ent rows idx newRows)
  (setq ent (stab_pick_table))

  (if ent
    (progn
      (setq rows (stab_get_rows ent))

      (if (<= (length rows) 1)
        (princ "\nImpossible de supprimer : le tableau doit garder au moins une ligne.")
        (progn
          (setq idx (stab_select_line_dialog rows "Supprimer une ligne du tableau"))

          (if idx
            (progn
              (setq newRows (stab_remove_nth idx rows))
              (stab_set_rows ent newRows)
              (stab_refresh_table ent)
              (princ "\nLigne supprimee.")
            )
          )
        )
      )
    )
  )
)

(defun stab_action_maj ()
  (stab_refresh_all)
  (princ "\nTableaux mis a jour.")
)

(defun c:S_TABLEAU (/ choix)
  (stab_regapp)
  (stab_start_reactor)

  (setq choix (stab_main_dialog))

  (cond
    ((= choix "CREER")
      (stab_action_creer)
    )
    ((= choix "AJOUTER")
      (stab_action_ajouter)
    )
    ((= choix "MODIFIER")
      (stab_action_modifier)
    )
    ((= choix "SUPPRIMER")
      (stab_action_supprimer)
    )
    ((= choix "MAJ")
      (stab_action_maj)
    )
  )

  (princ)
)

(stab_regapp)
(stab_start_reactor)



