<cfcomponent displayname="PDFUtility" output="false"
    hint="PDF signing utility using Apache PDFBox 3.x for ColdFusion 2021.">

    <!---
    ================================================================
    Requirements
    ================================================================
    PDFBox 3.x JARs must be in D:\PDF-Utility\jars\ (loaded via
    Application.cfc this.javaSettings).  Required files:
        pdfbox-3.0.x.jar
        fontbox-3.0.x.jar
        commons-logging-1.x.jar

    Coordinate system: PDFBox origin is BOTTOM-LEFT (points).
    US Letter = 612 x 792 pt.  1 inch = 72 points.
    ================================================================

    addSignatureLine — dynamic constants
    -----------------------------------------------
    SIG_MARGIN  : margin (pt) from the right and bottom edges where
                  the signature image is placed.
    RENDER_DPI  : DPI used to rasterise the signature template.
                  Higher = sharper image, larger output file.

    addSignatureText — text placement constants
    -----------------------------------------------
    FONT_SIZE : point size for the signer name and date fields.
                Text is positioned dynamically below the detected
                signature image using the same right-side placement
                logic as addSignatureLine.
    ================================================================
    --->

    <!--- addSignatureLine --->
    <cfset VARIABLES.SIG_MARGIN  = 90  /><!--- 0.25 in from right and bottom edges --->
    <cfset VARIABLES.RENDER_DPI  = 150 />

    <!--- addSignatureText --->
    <cfset VARIABLES.FONT_SIZE = 11  />


    <!---
    ================================================================
    addSignatureLine
    ================================================================
    Phase 1 — Content detection (36 DPI preview scan)
      Renders the signature PDF at 36 DPI and pixel-scans it to find
      the tightest bounding box of all non-white content.  Early-exit
      scanning (top/bottom/left/right edges) keeps this fast.

    Phase 2 — Crop to signature content (RENDER_DPI quality)
      Renders the same page at full quality and crops to the bounds
      detected in Phase 1, extracting only the signature region.

    Phase 3 — Stamp at bottom-right (natural size)
      Converts crop pixel dimensions to PDF points (72pt/inch at
      RENDER_DPI) to get the natural signature size.  Right-aligns
      with SIG_MARGIN from the right and bottom edges.  No lines.

    @PDFPath          Absolute path to the source PDF.
    @SignaturePDFPath Absolute path to the signature template PDF.
    @SaveToFolder     Absolute path to the destination folder.
    @return           Absolute path of the newly created PDF.

    Throws:
      PDFUtility.InvalidArgument — missing / non-existent path
      PDFUtility.ProcessingError — PDFBox operation failed
      PDFUtility.WriteError      — output file not created on disk
    ================================================================
    --->
    <cffunction name="addSignatureLine" access="public" returntype="string" output="false"
        hint="Auto-detects signature content bounds, crops to just the signature, stamps at the bottom of the last page.">

        <cfargument name="PDFPath"          type="string" required="true" />
        <cfargument name="SignaturePDFPath" type="string" required="true" />
        <cfargument name="SaveToFolder"     type="string" required="true" />

        <cfif NOT fileExists(arguments.PDFPath)>
            <cfthrow type="PDFUtility.InvalidArgument"
                message="Source PDF does not exist."
                detail="PDFPath: #arguments.PDFPath#" />
        </cfif>

        <cfif NOT directoryExists(arguments.SaveToFolder)>
            <cfthrow type="PDFUtility.InvalidArgument"
                message="Destination folder does not exist."
                detail="SaveToFolder: #arguments.SaveToFolder#" />
        </cfif>

        <cfset var outputPath = "" />
        <cfset var sourceDoc  = "" />
        <cfset var sigDoc     = "" />

        <cftry>

            <cfset var jFile           = createObject("java", "java.io.File") />
            <cfset var Loader          = createObject("java", "org.apache.pdfbox.Loader") />
            <cfset var PDFRenderer     = createObject("java", "org.apache.pdfbox.rendering.PDFRenderer") />
            <cfset var LosslessFactory = createObject("java", "org.apache.pdfbox.pdmodel.graphics.image.LosslessFactory") />
            <cfset var AppendMode      = createObject("java", "org.apache.pdfbox.pdmodel.PDPageContentStream$AppendMode") />
            <cfset var PDPageCS        = createObject("java", "org.apache.pdfbox.pdmodel.PDPageContentStream") />

            <cfset sourceDoc = Loader.loadPDF(jFile.init(arguments.PDFPath)) />
            <cfset sourceDoc.setAllSecurityToBeRemoved(javaCast("boolean", true)) />
            <cfset sigDoc    = Loader.loadPDF(jFile.init(arguments.SignaturePDFPath)) />

            <cfset var lastPage  = sourceDoc.getPage(javaCast("int", sourceDoc.getNumberOfPages() - 1)) />
            <cfset var pageWidth = lastPage.getMediaBox().getWidth() />

            <!---
            ══ PHASE 1 — Detect signature content bounds via low-DPI pixel scan ══

            Render the signature PDF at 36 DPI → tiny image (~306×396 px for US
            letter).  Scan that image to find the tightest rectangle that
            contains all non-white pixels.  A pixel is "non-white" when any of
            its R/G/B channels is below THRESHOLD (240).

            Scanning with early-exit per edge (top, bottom, left, right) keeps
            this fast even for full-page templates.
            ═══════════════════════════════════════════════════════════════════
            --->
            <cfset var SCAN_DPI  = 36  />
            <cfset var THRESHOLD = 240 /><!--- 0-255: lower catches lighter content --->
            <cfset var PAD_PX    = 4   /><!--- extra pixels added around the detected bounds --->

            <cfset var sigRenderer = PDFRenderer.init(sigDoc) />
            <cfset var scanImg     = sigRenderer.renderImageWithDPI(javaCast("int", 0), javaCast("float", SCAN_DPI)) />
            <cfset var scanW = scanImg.getWidth() />
            <cfset var scanH = scanImg.getHeight() />

            <!--- Default bounds = full image (fallback when the page is all-white) --->
            <cfset var rawMinX = 0 />
            <cfset var rawMinY = 0 />
            <cfset var rawMaxX = scanW - 1 />
            <cfset var rawMaxY = scanH - 1 />

            <!--- Scan top → find first row that contains a non-white pixel --->
            <cfset var hit = false />
            <cfloop index="py" from="0" to="#(scanH-1)#">
                <cfif hit><cfbreak /></cfif>
                <cfloop index="px" from="0" to="#(scanW-1)#">
                    <cfset var _rgb = scanImg.getRGB(javaCast("int",px), javaCast("int",py)) />
                    <cfif bitAnd(bitSHRN(_rgb,16),255) LT THRESHOLD
                       OR bitAnd(bitSHRN(_rgb, 8),255) LT THRESHOLD
                       OR bitAnd(_rgb,255)              LT THRESHOLD>
                        <cfset rawMinY = py /><cfset hit = true /><cfbreak />
                    </cfif>
                </cfloop>
            </cfloop>

            <!--- Scan bottom → find last row that contains a non-white pixel --->
            <cfset hit = false />
            <cfloop index="py" from="#(scanH-1)#" to="0" step="-1">
                <cfif hit><cfbreak /></cfif>
                <cfloop index="px" from="0" to="#(scanW-1)#">
                    <cfset _rgb = scanImg.getRGB(javaCast("int",px), javaCast("int",py)) />
                    <cfif bitAnd(bitSHRN(_rgb,16),255) LT THRESHOLD
                       OR bitAnd(bitSHRN(_rgb, 8),255) LT THRESHOLD
                       OR bitAnd(_rgb,255)              LT THRESHOLD>
                        <cfset rawMaxY = py /><cfset hit = true /><cfbreak />
                    </cfif>
                </cfloop>
            </cfloop>

            <!--- Scan left → first column with a non-white pixel (only within content rows) --->
            <cfset hit = false />
            <cfloop index="px" from="0" to="#(scanW-1)#">
                <cfif hit><cfbreak /></cfif>
                <cfloop index="py" from="#rawMinY#" to="#rawMaxY#">
                    <cfset _rgb = scanImg.getRGB(javaCast("int",px), javaCast("int",py)) />
                    <cfif bitAnd(bitSHRN(_rgb,16),255) LT THRESHOLD
                       OR bitAnd(bitSHRN(_rgb, 8),255) LT THRESHOLD
                       OR bitAnd(_rgb,255)              LT THRESHOLD>
                        <cfset rawMinX = px /><cfset hit = true /><cfbreak />
                    </cfif>
                </cfloop>
            </cfloop>

            <!--- Scan right → last column with a non-white pixel (only within content rows) --->
            <cfset hit = false />
            <cfloop index="px" from="#(scanW-1)#" to="0" step="-1">
                <cfif hit><cfbreak /></cfif>
                <cfloop index="py" from="#rawMinY#" to="#rawMaxY#">
                    <cfset _rgb = scanImg.getRGB(javaCast("int",px), javaCast("int",py)) />
                    <cfif bitAnd(bitSHRN(_rgb,16),255) LT THRESHOLD
                       OR bitAnd(bitSHRN(_rgb, 8),255) LT THRESHOLD
                       OR bitAnd(_rgb,255)              LT THRESHOLD>
                        <cfset rawMaxX = px /><cfset hit = true /><cfbreak />
                    </cfif>
                </cfloop>
            </cfloop>

            <!--- Expand by PAD_PX and clamp to the image boundary --->
            <cfset var bMinX = max(0,       rawMinX - PAD_PX) />
            <cfset var bMinY = max(0,       rawMinY - PAD_PX) />
            <cfset var bMaxX = min(scanW-1, rawMaxX + PAD_PX) />
            <cfset var bMaxY = min(scanH-1, rawMaxY + PAD_PX) />

            <!---
            ══ PHASE 2 — Render at full quality and crop to detected bounds ══

            Render the same signature page at RENDER_DPI.  Scale the scan-DPI
            bounds up to RENDER_DPI coordinates, then extract that rectangle
            from the high-res image with BufferedImage.getSubimage().
            ═══════════════════════════════════════════════════════════════════
            --->
            <cfset var fullImg   = sigRenderer.renderImageWithDPI(javaCast("int", 0), javaCast("float", VARIABLES.RENDER_DPI)) />
            <cfset var cropScale = VARIABLES.RENDER_DPI / SCAN_DPI />

            <cfset var cropLeft   = max(0,                int(bMinX * cropScale)) />
            <cfset var cropTop    = max(0,                int(bMinY * cropScale)) />
            <cfset var cropRight  = min(fullImg.getWidth(),  ceiling((bMaxX + 1) * cropScale)) />
            <cfset var cropBottom = min(fullImg.getHeight(), ceiling((bMaxY + 1) * cropScale)) />
            <cfset var cropW      = max(1, cropRight  - cropLeft) />
            <cfset var cropH      = max(1, cropBottom - cropTop)  />

            <cfset var croppedImg = fullImg.getSubimage(
                javaCast("int", cropLeft),
                javaCast("int", cropTop),
                javaCast("int", cropW),
                javaCast("int", cropH)
            ) />

            <cfset var pdImage = LosslessFactory.createFromImage(sourceDoc, croppedImg) />

            <!---
            ══ PHASE 3 — Place cropped signature at the bottom-right of the last page ══

            Natural size: convert crop pixel dimensions to PDF points at
            72pt/inch for RENDER_DPI.  Right-align with SIG_MARGIN from
            the right edge; pin SIG_MARGIN from the bottom edge.
            ═══════════════════════════════════════════════════════════════════
            --->
            <cfset var stampW = cropW * 72.0 / VARIABLES.RENDER_DPI />
            <cfset var stampH = cropH * 72.0 / VARIABLES.RENDER_DPI />

            <cfset var stampX = pageWidth - stampW - VARIABLES.SIG_MARGIN />
            <cfset var stampY = VARIABLES.SIG_MARGIN />

            <cfset var cs = PDPageCS.init(
                sourceDoc, lastPage, AppendMode.APPEND,
                javaCast("boolean", true), javaCast("boolean", true)
            ) />

            <cftry>
                <cfset cs.drawImage(
                    pdImage,
                    javaCast("float", stampX),
                    javaCast("float", stampY),
                    javaCast("float", stampW),
                    javaCast("float", stampH)
                ) />

                <cfcatch type="any">
                    <cftry><cfset cs.close() /><cfcatch type="any" /></cftry>
                    <cfrethrow />
                </cfcatch>
            </cftry>
            <cfset cs.close() />

            <cfset outputPath = buildOutputPath(arguments.SaveToFolder) />
            <cfset sourceDoc.save(jFile.init(outputPath)) />

            <cfcatch type="any">
                <cfthrow type="PDFUtility.ProcessingError"
                    message="Failed to stamp signature onto PDF."
                    detail="#cfcatch.message# | Source: #arguments.PDFPath#" />
            </cfcatch>
            <cffinally>
                <cfif isObject(sourceDoc)>
                    <cftry><cfset sourceDoc.close() /><cfcatch type="any" /></cftry>
                </cfif>
                <cfif isObject(sigDoc)>
                    <cftry><cfset sigDoc.close() /><cfcatch type="any" /></cftry>
                </cfif>
            </cffinally>

        </cftry>

        <cfif NOT fileExists(outputPath)>
            <cfthrow type="PDFUtility.WriteError"
                message="Output PDF was not written to disk."
                detail="Expected: #outputPath#" />
        </cfif>

        <cfreturn outputPath />
    </cffunction>


    <!---
    ================================================================
    addSignatureText
    ================================================================
    Opens PDFPath, runs the same Phase 1 content-detection scan on
    SignaturePDFPath to compute where addSignatureLine placed the
    stamp, then writes SignatureText and today's date (MM/DD/YYYY)
    just below the bottom edge of that signature image.

    Name is left-aligned with the signature image; date is placed
    roughly in the right half of the same width, on the same baseline.

    @PDFPath          Absolute path to the source PDF (must already
                      have the signature image from addSignatureLine).
    @SignaturePDFPath Absolute path to the signature template PDF
                      (same one used in addSignatureLine).
    @SignatureText    Signer name to print below the signature.
    @SaveToFolder     Absolute path to the destination folder.
    @return           Absolute path of the newly created PDF.

    Throws:
      PDFUtility.InvalidArgument — missing / non-existent path
      PDFUtility.ProcessingError — PDFBox operation failed
      PDFUtility.WriteError      — output file not created on disk
    ================================================================
    --->
    <cffunction name="addSignatureText" access="public" returntype="string" output="false"
        hint="Writes SignatureText and today's date on the signature line.">

        <cfargument name="PDFPath"       type="string" required="true" />
        <cfargument name="SignatureText" type="string" required="true" />
        <cfargument name="SaveToFolder"  type="string" required="true" />
        <cfargument name="SignatureFont" type="string" required="false" default="TIMES_BOLD_ITALIC" />

        <!--- Validation --->
        <cfif NOT fileExists(arguments.PDFPath)>
            <cfthrow type="PDFUtility.InvalidArgument"
                message="Source PDF does not exist."
                detail="PDFPath: #arguments.PDFPath#" />
        </cfif>

        <cfif NOT directoryExists(arguments.SaveToFolder)>
            <cfthrow type="PDFUtility.InvalidArgument"
                message="Destination folder does not exist."
                detail="SaveToFolder: #arguments.SaveToFolder#" />
        </cfif>

        <cfset var outputPath  = "" />
        <cfset var doc         = "" />
        <cfset var currentDate = dateFormat(now(), "mm/dd/yyyy") />

        <cftry>

            <cfset var jFile       = createObject("java", "java.io.File") />
            <cfset var Loader      = createObject("java", "org.apache.pdfbox.Loader") />
            <cfset var AppendMode  = createObject("java", "org.apache.pdfbox.pdmodel.PDPageContentStream$AppendMode") />
            <cfset var PDPageCS    = createObject("java", "org.apache.pdfbox.pdmodel.PDPageContentStream") />
            <cfset var FontName    = createObject("java", "org.apache.pdfbox.pdmodel.font.Standard14Fonts$FontName") />
            <cfset var PDType1Font = createObject("java", "org.apache.pdfbox.pdmodel.font.PDType1Font") />

            <cfset doc = Loader.loadPDF(jFile.init(arguments.PDFPath)) />
            <cfset doc.setAllSecurityToBeRemoved(javaCast("boolean", true)) />

            <cfset var lastPage = doc.getPage(
                javaCast("int", doc.getNumberOfPages() - 1)
            ) />

            <!--- <cfset var font = PDType1Font.init(FontName.HELVETICA_BOLD) /> --->
            <cfset var selectedFont = evaluate("FontName." & arguments.SignatureFont) />
            <cfset var font = PDType1Font.init(selectedFont) />

            <!---
                Adjust these coordinates after testing.
                These values assume the signature row is near the bottom
                of the last page.
            --->
            <cfset var signatureX = 110 />
            <cfset var signatureY = 130 />

            <cfset var dateX = 440 />
            <cfset var dateY = 130 />

            <cfset var cs = PDPageCS.init(
                doc,
                lastPage,
                AppendMode.APPEND,
                javaCast("boolean", true),
                javaCast("boolean", true)
            ) />

            <cftry>

                <!--- Signature Text --->
                <cfset cs.beginText() />
                <cfset cs.setFont(font, javaCast("float", VARIABLES.FONT_SIZE)) />
                <cfset cs.newLineAtOffset(
                    javaCast("float", signatureX),
                    javaCast("float", signatureY)
                ) />
                <cfset cs.showText(arguments.SignatureText) />
                <cfset cs.endText() />

                <!--- Date --->
                <cfset cs.beginText() />
                <cfset cs.setFont(font, javaCast("float", VARIABLES.FONT_SIZE)) />
                <cfset cs.newLineAtOffset(
                    javaCast("float", dateX),
                    javaCast("float", dateY)
                ) />
                <cfset cs.showText(currentDate) />
                <cfset cs.endText() />

                <cfcatch type="any">
                    <cftry>
                        <cfset cs.close() />
                        <cfcatch type="any"></cfcatch>
                    </cftry>
                    <cfrethrow />
                </cfcatch>

            </cftry>

            <cfset cs.close() />

            <cfset outputPath = buildOutputPath(arguments.SaveToFolder) />
            <cfset doc.save(jFile.init(outputPath)) />

            <cfcatch type="any">
                <cfthrow type="PDFUtility.ProcessingError"
                    message="Failed to overlay signature text on PDF."
                    detail="#cfcatch.message# | PDFPath: #arguments.PDFPath#" />
            </cfcatch>

            <cffinally>
                <cfif isObject(doc)>
                    <cftry>
                        <cfset doc.close() />
                        <cfcatch type="any"></cfcatch>
                    </cftry>
                </cfif>
            </cffinally>

        </cftry>

        <cfif NOT fileExists(outputPath)>
            <cfthrow type="PDFUtility.WriteError"
                message="Signed PDF was not written to disk."
                detail="Expected: #outputPath#" />
        </cfif>

        <cfreturn outputPath />

    </cffunction>


    <!---
    ================================================================
    buildOutputPath  (private)
    ================================================================
    --->
    <cffunction name="buildOutputPath" access="private" returntype="string" output="false">
        <cfargument name="folder" type="string" required="true" />
        <cfset var sep = right(trim(arguments.folder), 1) />
        <cfif sep NEQ "/" AND sep NEQ "\">
            <cfreturn arguments.folder & "\" & createUUID() & ".pdf" />
        <cfelse>
            <cfreturn arguments.folder & createUUID() & ".pdf" />
        </cfif>
    </cffunction>

</cfcomponent>
