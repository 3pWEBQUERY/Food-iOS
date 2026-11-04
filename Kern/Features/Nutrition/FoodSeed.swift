import Foundation

/// Generische Referenz-Lebensmittel mit DACH-Fokus (Richtwerte pro 100 g bzw. 100 ml).
/// Bewusst ohne Markenprodukte und ohne Barcodes – Markenprodukte kommen über den
/// Barcode-Scanner aus dem eigenen Katalog oder Open Food Facts.
enum FoodSeed {
    static func makeItems() -> [FoodItem] {
        var items: [FoodItem] = []

        func add(_ name: String, _ category: String, _ kcal: Double, _ p: Double, _ c: Double, _ f: Double,
                 sugar: Double? = nil, fiber: Double? = nil, salt: Double? = nil, sat: Double? = nil,
                 liquid: Bool = false, servings: [(String, Double)] = [], syn: [String] = [],
                 ca: Double? = nil, fe: Double? = nil, mg: Double? = nil, k: Double? = nil,
                 vitC: Double? = nil, vitD: Double? = nil, b12: Double? = nil, caffeine: Double? = nil) {
            let nutrients = Nutrients(kcal: kcal, protein: p, carbs: c, fat: f, sugar: sugar, saturatedFat: sat,
                                      fiber: fiber, salt: salt, calciumMg: ca, ironMg: fe, magnesiumMg: mg,
                                      potassiumMg: k, vitaminCMg: vitC, vitaminDUg: vitD, vitaminB12Ug: b12,
                                      caffeineMg: caffeine)
            let sizes = servings.map { ServingSize(label: $0.0, grams: $0.1) }
            items.append(FoodItem(name: name, category: category, source: .reference, quality: .reference,
                                  per100: nutrients, servings: sizes, isLiquid: liquid, synonyms: syn))
        }

        // MARK: Brot & Backwaren
        let bread = "Brot & Backwaren"
        add("Zopf", bread, 300, 9, 48, 8, sugar: 4, fiber: 2, salt: 1.2, servings: [("1 Scheibe", 40)], syn: ["Butterzopf", "Hefezopf"])
        add("Ruchbrot", bread, 240, 8, 47, 1.3, sugar: 1.5, fiber: 5, salt: 1.3, servings: [("1 Scheibe", 50)], syn: ["Brot"])
        add("Vollkornbrot", bread, 220, 8, 39, 2, sugar: 3, fiber: 7.5, salt: 1.1, servings: [("1 Scheibe", 50)], syn: ["Brot", "Schwarzbrot"], mg: 70)
        add("Halbweissbrot", bread, 255, 8.5, 50, 1.5, sugar: 2, fiber: 3.5, salt: 1.3, servings: [("1 Scheibe", 50)], syn: ["Brot", "Mischbrot"])
        add("Toastbrot", bread, 265, 8, 48, 4, sugar: 5, fiber: 3, salt: 1.2, servings: [("1 Scheibe", 25)], syn: ["Toast"])
        add("Brötchen", bread, 270, 9, 54, 1.5, sugar: 2, fiber: 2.5, salt: 1.4, servings: [("1 Stück", 50)], syn: ["Semmel", "Weggli", "Schrippe", "Bürli"])
        add("Laugenbrezel", bread, 290, 8.5, 57, 2.5, sugar: 1.5, fiber: 2.5, salt: 2.5, servings: [("1 Brezel", 80)], syn: ["Brezel", "Bretzel", "Breze"])
        add("Buttergipfeli", bread, 410, 8, 45, 21, sugar: 7, fiber: 2, salt: 1.0, sat: 13, servings: [("1 Stück", 45)], syn: ["Gipfeli", "Croissant", "Hörnchen"])
        add("Knäckebrot", bread, 340, 10, 63, 2, sugar: 2, fiber: 16, salt: 1.1, servings: [("1 Scheibe", 10)])
        add("Apfelwähe", bread, 210, 3.5, 28, 9, sugar: 14, fiber: 1.5, salt: 0.3, servings: [("1 Stück", 150)], syn: ["Apfelkuchen", "Wähe"])
        add("Rüeblitorte", bread, 380, 6, 45, 19, sugar: 33, fiber: 2.5, salt: 0.3, servings: [("1 Stück", 100)], syn: ["Karottenkuchen", "Möhrenkuchen"])
        add("Apfelstrudel", bread, 230, 3, 32, 10, sugar: 15, fiber: 1.8, salt: 0.2, servings: [("1 Stück", 150)], syn: ["Strudel"])
        add("Basler Läckerli", bread, 380, 6, 72, 6, sugar: 55, fiber: 3, salt: 0.1, servings: [("1 Stück", 15)], syn: ["Läckerli", "Lebkuchen"])

        // MARK: Getreide & Beilagen
        let grain = "Getreide & Beilagen"
        add("Haferflocken", grain, 370, 13.5, 59, 7, sugar: 1, fiber: 10, salt: 0.01, servings: [("1 Portion", 50), ("1 EL", 10)], syn: ["Hafer", "Porridge", "Oats"], fe: 4.5, mg: 130)
        add("Birchermüesli", grain, 110, 3.5, 16, 3.5, sugar: 10, fiber: 2, salt: 0.05, servings: [("1 Schale", 200)], syn: ["Bircher", "Müsli", "Overnight Oats"])
        add("Müesli ohne Zuckerzusatz", grain, 360, 10, 62, 6, sugar: 15, fiber: 8, salt: 0.05, servings: [("1 Portion", 50)], syn: ["Müsli", "Muesli"])
        add("Cornflakes", grain, 375, 7, 84, 0.9, sugar: 8, fiber: 3, salt: 1.3, servings: [("1 Portion", 30)], syn: ["Flakes"])
        add("Reis, gekocht", grain, 130, 2.7, 28, 0.3, sugar: 0.1, fiber: 0.4, salt: 0, servings: [("1 Portion", 180)], syn: ["Reis", "Basmati", "Jasmin"])
        add("Reis, roh", grain, 350, 7, 78, 0.6, sugar: 0.3, fiber: 1.4, salt: 0, servings: [("1 Portion", 70)], syn: ["Reis"])
        add("Vollkornreis, gekocht", grain, 120, 2.8, 25, 0.9, sugar: 0.3, fiber: 1.6, salt: 0, servings: [("1 Portion", 180)], syn: ["Naturreis", "Reis"])
        add("Teigwaren, gekocht", grain, 150, 5.5, 30, 0.9, sugar: 0.6, fiber: 1.8, salt: 0, servings: [("1 Portion", 200)], syn: ["Pasta", "Nudeln", "Spaghetti", "Penne", "Hörnli"])
        add("Teigwaren, roh", grain, 355, 12.5, 71, 1.5, sugar: 3, fiber: 3, salt: 0, servings: [("1 Portion", 80)], syn: ["Pasta", "Nudeln", "Spaghetti"])
        add("Vollkornteigwaren, gekocht", grain, 140, 6, 26, 1, sugar: 0.8, fiber: 4, salt: 0, servings: [("1 Portion", 200)], syn: ["Vollkornpasta", "Nudeln"])
        add("Spätzli, gekocht", grain, 150, 5.5, 26, 2.5, sugar: 0.5, fiber: 1.5, salt: 0.4, servings: [("1 Portion", 200)], syn: ["Spätzle", "Knöpfli"])
        add("Gnocchi", grain, 140, 3.5, 30, 0.5, sugar: 0.5, fiber: 1.5, salt: 1, servings: [("1 Portion", 200)])
        add("Couscous, gekocht", grain, 112, 3.8, 23, 0.2, sugar: 0.1, fiber: 1.4, salt: 0, servings: [("1 Portion", 150)])
        add("Quinoa, gekocht", grain, 120, 4.4, 21, 1.9, sugar: 0.9, fiber: 2.8, salt: 0, servings: [("1 Portion", 150)], mg: 64)
        add("Bulgur, gekocht", grain, 83, 3, 19, 0.2, sugar: 0.1, fiber: 4.5, salt: 0, servings: [("1 Portion", 150)])
        add("Polenta, gekocht", grain, 75, 1.7, 16, 0.3, sugar: 0.2, fiber: 0.8, salt: 0.3, servings: [("1 Portion", 250)], syn: ["Maisgriess", "Mais"])
        add("Kartoffeln, gekocht", grain, 75, 2, 16, 0.1, sugar: 0.8, fiber: 1.8, salt: 0, servings: [("1 mittelgrosse", 100), ("1 Portion", 200)], syn: ["Erdäpfel", "Salzkartoffeln", "Härdöpfel"], k: 400, vitC: 12)
        add("Süsskartoffel, gekocht", grain, 76, 1.4, 17.7, 0.1, sugar: 5.7, fiber: 2.5, salt: 0, servings: [("1 Stück", 150)], syn: ["Batate"])
        add("Rösti", grain, 140, 2.5, 17, 7, sugar: 0.5, fiber: 2, salt: 0.8, servings: [("1 Portion", 200)], syn: ["Röschti"])
        add("Kartoffelstock", grain, 95, 2, 13, 3.5, sugar: 1.5, fiber: 1.2, salt: 0.6, servings: [("1 Portion", 200)], syn: ["Kartoffelpüree", "Stocki", "Erdäpfelpüree"])
        add("Pommes frites", grain, 290, 3.5, 36, 15, sugar: 0.5, fiber: 3.5, salt: 0.5, servings: [("1 Portion", 150)], syn: ["Fritten", "Pommes"])

        // MARK: Milchprodukte & Eier
        let dairy = "Milchprodukte & Eier"
        add("Vollmilch 3.5 %", dairy, 65, 3.3, 4.8, 3.6, sugar: 4.8, fiber: 0, salt: 0.1, sat: 2.3, liquid: true, servings: [("1 Glas", 200), ("1 Tasse", 150)], syn: ["Milch"], ca: 120, b12: 0.4)
        add("Milch teilentrahmt 2.5 %", dairy, 56, 3.4, 4.8, 2.5, sugar: 4.8, fiber: 0, salt: 0.1, sat: 1.6, liquid: true, servings: [("1 Glas", 200)], syn: ["Milch", "Milchdrink"], ca: 120)
        add("Magermilch", dairy, 35, 3.5, 4.9, 0.1, sugar: 4.9, fiber: 0, salt: 0.1, liquid: true, servings: [("1 Glas", 200)], syn: ["Milch", "Entrahmte Milch"], ca: 125)
        add("Haferdrink", dairy, 45, 0.5, 7, 1.5, sugar: 4, fiber: 0.8, salt: 0.1, liquid: true, servings: [("1 Glas", 200)], syn: ["Hafermilch", "Oat"])
        add("Sojadrink", dairy, 39, 3.3, 1.5, 1.9, sugar: 1, fiber: 0.5, salt: 0.1, liquid: true, servings: [("1 Glas", 200)], syn: ["Sojamilch"])
        add("Mandeldrink", dairy, 24, 0.5, 3, 1.1, sugar: 3, fiber: 0.3, salt: 0.1, liquid: true, servings: [("1 Glas", 200)], syn: ["Mandelmilch"])
        add("Joghurt nature", dairy, 70, 4, 5, 3.5, sugar: 5, fiber: 0, salt: 0.13, servings: [("1 Becher", 180)], syn: ["Jogurt", "Naturjoghurt"], ca: 130)
        add("Fruchtjoghurt", dairy, 100, 3.5, 15, 2.8, sugar: 14, fiber: 0.3, salt: 0.1, servings: [("1 Becher", 180)], syn: ["Jogurt"])
        add("Griechischer Joghurt 10 %", dairy, 120, 5, 4, 10, sugar: 4, fiber: 0, salt: 0.1, servings: [("1 Portion", 150)], syn: ["Joghurt griechische Art"])
        add("Skyr nature", dairy, 63, 11, 4, 0.2, sugar: 4, fiber: 0, salt: 0.1, servings: [("1 Becher", 170)], syn: ["Skyr"])
        add("Magerquark", dairy, 67, 12, 4, 0.3, sugar: 4, fiber: 0, salt: 0.1, servings: [("1 Portion", 250), ("1 EL", 30)], syn: ["Quark", "Topfen"])
        add("Halbfettquark", dairy, 110, 10, 3.5, 6, sugar: 3.5, fiber: 0, salt: 0.1, servings: [("1 Portion", 250)], syn: ["Quark", "Topfen"])
        add("Hüttenkäse", dairy, 98, 11.5, 3, 4.5, sugar: 3, fiber: 0, salt: 0.8, servings: [("1 Becher", 200)], syn: ["Cottage Cheese", "Hüttechäs"])
        add("Mozzarella", dairy, 250, 18, 1, 19, sugar: 1, fiber: 0, salt: 0.5, sat: 13, servings: [("1 Kugel", 125)], ca: 400)
        add("Gruyère", dairy, 410, 27, 0, 33, sugar: 0, fiber: 0, salt: 1.5, sat: 20, servings: [("1 Portion", 30)], syn: ["Greyerzer", "Käse", "Hartkäse"], ca: 900)
        add("Emmentaler", dairy, 380, 28, 0, 30, sugar: 0, fiber: 0, salt: 0.5, sat: 19, servings: [("1 Portion", 30), ("1 Scheibe", 20)], syn: ["Käse", "Emmentaler"], ca: 1000)
        add("Appenzeller", dairy, 390, 25, 0, 32, sugar: 0, fiber: 0, salt: 1.8, sat: 20, servings: [("1 Portion", 30)], syn: ["Käse"])
        add("Tilsiter", dairy, 360, 26, 0, 28, sugar: 0, fiber: 0, salt: 1.8, servings: [("1 Portion", 30)], syn: ["Käse"])
        add("Raclettekäse", dairy, 350, 23, 0, 28, sugar: 0, fiber: 0, salt: 1.8, sat: 18, servings: [("1 Scheibe", 40), ("1 Portion", 200)], syn: ["Raclette", "Käse"])
        add("Feta", dairy, 265, 16, 0.5, 22, sugar: 0.5, fiber: 0, salt: 2.8, servings: [("1 Portion", 50)], syn: ["Schafskäse"])
        add("Frischkäse", dairy, 250, 5.5, 3, 24, sugar: 3, fiber: 0, salt: 0.8, servings: [("1 Portion", 30)], syn: ["Doppelrahmfrischkäse"])
        add("Butter", dairy, 740, 0.7, 0.6, 82, sugar: 0.6, fiber: 0, salt: 0.02, sat: 52, servings: [("1 Portion", 10)], syn: ["Anke"])
        add("Vollrahm", dairy, 335, 2, 3, 35, sugar: 3, fiber: 0, salt: 0.1, sat: 22, servings: [("1 EL", 15)], syn: ["Sahne", "Schlagrahm", "Obers"])
        add("Kaffeerahm", dairy, 160, 3, 4, 15, sugar: 4, fiber: 0, salt: 0.1, servings: [("1 Portion", 12)], syn: ["Kaffeesahne"])
        add("Ei", dairy, 140, 12.5, 0.5, 10, sugar: 0.5, fiber: 0, salt: 0.35, sat: 3, servings: [("1 Ei (M)", 55), ("1 Ei (L)", 63)], syn: ["Eier", "Hühnerei", "Spiegelei", "Rührei"], fe: 1.8, vitD: 2, b12: 1.1)

        // MARK: Fleisch & Wurst
        let meat = "Fleisch & Wurst"
        add("Pouletbrust", meat, 105, 23.5, 0, 1.2, sugar: 0, fiber: 0, salt: 0.15, servings: [("1 Portion", 150)], syn: ["Hähnchenbrust", "Hühnerbrust", "Poulet", "Huhn"], b12: 0.4)
        add("Pouletschenkel", meat, 170, 18, 0, 11, sugar: 0, fiber: 0, salt: 0.2, servings: [("1 Stück", 150)], syn: ["Hähnchenschenkel", "Poulet"])
        add("Trutenbrust", meat, 105, 24, 0, 1, sugar: 0, fiber: 0, salt: 0.15, servings: [("1 Portion", 150)], syn: ["Putenbrust", "Truthahn"])
        add("Rindshackfleisch", meat, 215, 19, 0, 15, sugar: 0, fiber: 0, salt: 0.2, sat: 6.5, servings: [("1 Portion", 125)], syn: ["Hackfleisch", "Faschiertes", "Gehacktes"], fe: 2.2, b12: 2.5)
        add("Rindsplätzli", meat, 120, 22, 0, 3.5, sugar: 0, fiber: 0, salt: 0.15, servings: [("1 Portion", 150)], syn: ["Rindfleisch", "Steak", "Rindssteak"], fe: 2.3, b12: 2)
        add("Schweinsplätzli", meat, 110, 22, 0, 2, sugar: 0, fiber: 0, salt: 0.15, servings: [("1 Portion", 150)], syn: ["Schweineschnitzel", "Schweinefleisch"])
        add("Hackfleisch gemischt", meat, 250, 18, 0, 20, sugar: 0, fiber: 0, salt: 0.2, servings: [("1 Portion", 125)], syn: ["Hackfleisch", "Faschiertes"])
        add("Cervelat", meat, 275, 12, 1, 25, sugar: 0.5, fiber: 0, salt: 2.2, servings: [("1 Stück", 100)], syn: ["Servela", "Wurst"])
        add("Kalbsbratwurst", meat, 255, 12, 1, 22.5, sugar: 0.5, fiber: 0, salt: 1.8, servings: [("1 Stück", 130)], syn: ["Bratwurst", "Wurst", "Olma"])
        add("Wienerli", meat, 260, 12, 1, 23, sugar: 0.5, fiber: 0, salt: 2, servings: [("1 Paar", 100)], syn: ["Wiener Würstchen", "Frankfurter", "Würstel"])
        add("Bündnerfleisch", meat, 225, 39, 1, 7, sugar: 0.5, fiber: 0, salt: 5.5, servings: [("1 Portion", 30)], syn: ["Trockenfleisch"])
        add("Hinterschinken", meat, 115, 19, 1, 3.5, sugar: 1, fiber: 0, salt: 2.3, servings: [("1 Scheibe", 25)], syn: ["Schinken", "Kochschinken"])
        add("Salami", meat, 420, 22, 1, 37, sugar: 0.5, fiber: 0, salt: 4.5, servings: [("1 Scheibe", 8), ("1 Portion", 30)], syn: ["Wurst"])
        add("Bratspeck", meat, 400, 13, 0.5, 39, sugar: 0, fiber: 0, salt: 3, servings: [("1 Tranche", 15)], syn: ["Speck", "Bacon"])
        add("Wiener Schnitzel", meat, 220, 18, 12, 11, sugar: 0.5, fiber: 0.5, salt: 0.6, servings: [("1 Stück", 150)], syn: ["Schnitzel", "paniert"])
        add("Zürcher Geschnetzeltes", meat, 150, 13, 3, 9.5, sugar: 1.5, fiber: 0.3, salt: 0.9, servings: [("1 Portion", 250)], syn: ["Geschnetzeltes"])

        // MARK: Fisch & Meeresfrüchte
        let fish = "Fisch & Meeresfrüchte"
        add("Lachs", fish, 200, 20, 0, 13, sugar: 0, fiber: 0, salt: 0.1, sat: 2.5, servings: [("1 Filet", 125)], syn: ["Lachsfilet", "Salm"], vitD: 16, b12: 3)
        add("Räucherlachs", fish, 180, 21, 0, 10, sugar: 0, fiber: 0, salt: 3, servings: [("1 Portion", 50)], syn: ["Lachs", "Rauchlachs"])
        add("Thunfisch in Wasser", fish, 115, 26, 0, 1, sugar: 0, fiber: 0, salt: 1, servings: [("1 Dose (abgetropft)", 130)], syn: ["Thon", "Tunfisch"], b12: 2.5)
        add("Thunfisch in Öl", fish, 200, 25, 0, 11, sugar: 0, fiber: 0, salt: 1, servings: [("1 Dose (abgetropft)", 130)], syn: ["Thon", "Tunfisch"])
        add("Kabeljau", fish, 77, 18, 0, 0.6, sugar: 0, fiber: 0, salt: 0.2, servings: [("1 Filet", 150)], syn: ["Dorsch", "Fisch"])
        add("Egli", fish, 85, 19, 0, 1, sugar: 0, fiber: 0, salt: 0.15, servings: [("1 Portion", 150)], syn: ["Barsch", "Flussbarsch", "Fisch"])
        add("Crevetten", fish, 85, 19, 0, 1, sugar: 0, fiber: 0, salt: 1, servings: [("1 Portion", 100)], syn: ["Garnelen", "Shrimps", "Scampi"])

        // MARK: Pflanzliche Proteine & Hülsenfrüchte
        let plant = "Hülsenfrüchte & Tofu"
        add("Tofu nature", plant, 125, 13, 1.5, 7.5, sugar: 0.5, fiber: 1, salt: 0.02, servings: [("1 Portion", 100)], syn: ["Tofu"], ca: 350, fe: 2.5)
        add("Tempeh", plant, 190, 19, 9, 11, sugar: 0.5, fiber: 5, salt: 0.02, servings: [("1 Portion", 100)])
        add("Linsen, gekocht", plant, 115, 9, 17, 0.4, sugar: 1.8, fiber: 8, salt: 0, servings: [("1 Portion", 150)], syn: ["Linsen"], fe: 3.3)
        add("Rote Linsen, roh", plant, 340, 24, 50, 1.5, sugar: 2, fiber: 11, salt: 0, servings: [("1 Portion", 70)], syn: ["Linsen"], fe: 7)
        add("Kichererbsen, gekocht", plant, 140, 7.5, 19, 2.5, sugar: 4.8, fiber: 7.5, salt: 0.3, servings: [("1 Portion", 150)], syn: ["Kichererbse", "Chickpeas"])
        add("Kidneybohnen, gekocht", plant, 110, 8, 15, 0.5, sugar: 0.5, fiber: 7, salt: 0.3, servings: [("1 Portion", 150)], syn: ["Bohnen", "rote Bohnen"])
        add("Edamame", plant, 120, 11, 7, 5, sugar: 2, fiber: 5, salt: 0.02, servings: [("1 Portion", 100)], syn: ["Sojabohnen"])
        add("Hummus", plant, 250, 7, 13, 18, sugar: 0.5, fiber: 6, salt: 1, servings: [("1 EL", 20), ("1 Portion", 50)], syn: ["Humus", "Kichererbsenpüree"])

        // MARK: Gemüse
        let veg = "Gemüse"
        add("Tomate", veg, 18, 0.9, 2.6, 0.2, sugar: 2.6, fiber: 1.2, salt: 0, servings: [("1 Stück", 120)], syn: ["Tomaten", "Paradeiser"], k: 240, vitC: 20)
        add("Gurke", veg, 12, 0.6, 1.8, 0.1, sugar: 1.7, fiber: 0.5, salt: 0, servings: [("1 Stück", 400)], syn: ["Salatgurke", "Gurken"])
        add("Karotte", veg, 36, 0.9, 7.6, 0.2, sugar: 4.7, fiber: 2.8, salt: 0.1, servings: [("1 Stück", 80)], syn: ["Rüebli", "Möhre", "Karotten"])
        add("Broccoli", veg, 34, 3, 4, 0.4, sugar: 1.7, fiber: 3, salt: 0.1, servings: [("1 Portion", 150)], syn: ["Brokkoli"], vitC: 90)
        add("Blumenkohl", veg, 25, 2, 3, 0.3, sugar: 2, fiber: 2, salt: 0, servings: [("1 Portion", 150)], syn: ["Karfiol"], vitC: 48)
        add("Spinat", veg, 23, 2.9, 1.4, 0.4, sugar: 0.4, fiber: 2.2, salt: 0.2, servings: [("1 Portion", 150)], syn: ["Blattspinat"], fe: 2.7, mg: 79)
        add("Kopfsalat", veg, 14, 1.2, 1.6, 0.2, sugar: 1.2, fiber: 1.3, salt: 0, servings: [("1 Portion", 80)], syn: ["Salat", "Blattsalat", "Nüsslisalat"])
        add("Peperoni rot", veg, 31, 1, 6, 0.3, sugar: 4.2, fiber: 2.1, salt: 0, servings: [("1 Stück", 160)], syn: ["Paprika", "Peperoni"], vitC: 128)
        add("Zucchetti", veg, 17, 1.2, 2.2, 0.3, sugar: 2, fiber: 1.1, salt: 0, servings: [("1 Stück", 200)], syn: ["Zucchini"])
        add("Aubergine", veg, 24, 1, 3.5, 0.2, sugar: 3, fiber: 3, salt: 0, servings: [("1 Stück", 250)], syn: ["Melanzani"])
        add("Zwiebel", veg, 40, 1.1, 8, 0.1, sugar: 4.2, fiber: 1.7, salt: 0, servings: [("1 Stück", 80)], syn: ["Zwiebeln", "Bölle"])
        add("Champignons", veg, 22, 3, 0.5, 0.3, sugar: 0.3, fiber: 1, salt: 0, servings: [("1 Portion", 100)], syn: ["Pilze", "Egerlinge"])
        add("Erbsen", veg, 80, 5.5, 11, 0.4, sugar: 4, fiber: 5, salt: 0, servings: [("1 Portion", 100)], syn: ["grüne Erbsen"])
        add("Mais, Konserve", veg, 90, 3, 16, 1.2, sugar: 4, fiber: 2.5, salt: 0.5, servings: [("1 Portion", 80)], syn: ["Mais", "Zuckermais"])
        add("Avocado", veg, 160, 2, 2, 15, sugar: 0.7, fiber: 6.7, salt: 0, servings: [("½ Avocado", 70)], k: 485)
        add("Lauch", veg, 31, 2, 3.3, 0.3, sugar: 2, fiber: 2.3, salt: 0, servings: [("1 Portion", 150)], syn: ["Porree"])
        add("Kohlrabi", veg, 27, 2, 4, 0.1, sugar: 3, fiber: 1.5, salt: 0, servings: [("1 Stück", 250)])
        add("Randen", veg, 43, 1.6, 8.4, 0.1, sugar: 7, fiber: 2.5, salt: 0.2, servings: [("1 Portion", 100)], syn: ["Rote Bete", "Rote Rüben", "Randen"])
        add("Fenchel", veg, 25, 1.2, 3, 0.2, sugar: 3, fiber: 3.3, salt: 0.1, servings: [("1 Knolle", 250)])
        add("Kürbis", veg, 26, 1, 5, 0.1, sugar: 2.8, fiber: 1.5, salt: 0, servings: [("1 Portion", 200)], syn: ["Butternut", "Hokkaido"])
        add("Grüne Bohnen", veg, 31, 1.8, 5, 0.2, sugar: 1.5, fiber: 2.7, salt: 0, servings: [("1 Portion", 150)], syn: ["Bohnen", "Fisolen"])
        add("Rosenkohl", veg, 43, 3.4, 5.5, 0.3, sugar: 2.2, fiber: 3.8, salt: 0, servings: [("1 Portion", 150)], syn: ["Kohlsprossen"], vitC: 85)
        add("Sauerkraut", veg, 20, 1, 3, 0.1, sugar: 1, fiber: 2.5, salt: 1.5, servings: [("1 Portion", 150)])
        add("Gemüsesuppe", veg, 35, 1.2, 5, 1, sugar: 2, fiber: 1.2, salt: 0.8, servings: [("1 Teller", 300)], syn: ["Suppe"])
        add("Bündner Gerstensuppe", veg, 75, 3, 9, 3, sugar: 1, fiber: 1.5, salt: 0.9, servings: [("1 Teller", 300)], syn: ["Gerstensuppe", "Suppe"])

        // MARK: Obst
        let fruit = "Obst"
        add("Apfel", fruit, 54, 0.3, 12, 0.2, sugar: 10, fiber: 2.3, salt: 0, servings: [("1 Stück", 150)], syn: ["Äpfel"])
        add("Banane", fruit, 93, 1.1, 20, 0.2, sugar: 17, fiber: 2, salt: 0, servings: [("1 Stück", 120)], syn: ["Bananen"], mg: 30, k: 370)
        add("Birne", fruit, 55, 0.4, 12.4, 0.2, sugar: 10, fiber: 3, salt: 0, servings: [("1 Stück", 160)], syn: ["Birnen"])
        add("Orange", fruit, 47, 1, 9, 0.2, sugar: 8.5, fiber: 2, salt: 0, servings: [("1 Stück", 150)], syn: ["Orangen", "Apfelsine"], vitC: 50)
        add("Mandarine", fruit, 50, 0.7, 10, 0.3, sugar: 9, fiber: 1.8, salt: 0, servings: [("1 Stück", 70)], syn: ["Clementine"])
        add("Erdbeeren", fruit, 33, 0.8, 5.5, 0.4, sugar: 5, fiber: 2, salt: 0, servings: [("1 Schale", 150)], syn: ["Erdbeere"], vitC: 60)
        add("Heidelbeeren", fruit, 42, 0.7, 7.4, 0.6, sugar: 7.4, fiber: 4.9, salt: 0, servings: [("1 Portion", 125)], syn: ["Blaubeeren"])
        add("Himbeeren", fruit, 36, 1.3, 4.8, 0.3, sugar: 4.4, fiber: 6.7, salt: 0, servings: [("1 Portion", 125)], syn: ["Himbeere"])
        add("Trauben", fruit, 70, 0.7, 16, 0.3, sugar: 16, fiber: 1.5, salt: 0, servings: [("1 Portion", 150)], syn: ["Weintrauben", "Trübli"])
        add("Kiwi", fruit, 51, 1, 9, 0.6, sugar: 9, fiber: 2.1, salt: 0, servings: [("1 Stück", 75)], vitC: 80)
        add("Ananas", fruit, 55, 0.5, 12, 0.2, sugar: 12, fiber: 1.2, salt: 0, servings: [("1 Portion", 150)])
        add("Mango", fruit, 62, 0.6, 13, 0.4, sugar: 13, fiber: 1.7, salt: 0, servings: [("1 Portion", 150)])
        add("Wassermelone", fruit, 30, 0.6, 7, 0.2, sugar: 6.2, fiber: 0.4, salt: 0, servings: [("1 Stück", 250)], syn: ["Melone"])
        add("Pfirsich", fruit, 42, 0.8, 9, 0.1, sugar: 8, fiber: 1.9, salt: 0, servings: [("1 Stück", 150)])
        add("Aprikose", fruit, 43, 0.9, 8.5, 0.1, sugar: 8, fiber: 1.6, salt: 0, servings: [("1 Stück", 45)], syn: ["Marille", "Aprikosen"])
        add("Zwetschgen", fruit, 47, 0.6, 10, 0.2, sugar: 9, fiber: 1.6, salt: 0, servings: [("1 Stück", 35)], syn: ["Pflaumen", "Zwetschken"])
        add("Kirschen", fruit, 63, 1, 14, 0.3, sugar: 13, fiber: 1.3, salt: 0, servings: [("1 Portion", 150)], syn: ["Chriesi"])
        add("Datteln, getrocknet", fruit, 290, 2, 66, 0.5, sugar: 64, fiber: 8, salt: 0, servings: [("1 Stück", 8)], syn: ["Datteln"], k: 650)
        add("Rosinen", fruit, 300, 2.5, 69, 0.5, sugar: 59, fiber: 3.7, salt: 0.05, servings: [("1 EL", 15)], syn: ["Sultaninen", "Weinbeeren"])

        // MARK: Nüsse & Samen
        let nuts = "Nüsse & Samen"
        add("Mandeln", nuts, 600, 21, 6, 52, sugar: 4, fiber: 12, salt: 0, sat: 4, servings: [("1 Handvoll", 30)], syn: ["Mandel"], ca: 260, mg: 270)
        add("Baumnüsse", nuts, 680, 15, 7, 65, sugar: 2.6, fiber: 6, salt: 0, servings: [("1 Handvoll", 30)], syn: ["Walnüsse", "Nüsse"], mg: 160)
        add("Haselnüsse", nuts, 650, 15, 7, 62, sugar: 4, fiber: 8, salt: 0, servings: [("1 Handvoll", 30)], syn: ["Nüsse"])
        add("Cashewnüsse", nuts, 590, 18, 27, 46, sugar: 6, fiber: 3, salt: 0, servings: [("1 Handvoll", 30)], syn: ["Cashew", "Nüsse"], mg: 290)
        add("Erdnüsse, geröstet", nuts, 600, 25, 12, 50, sugar: 4, fiber: 8, salt: 0.5, servings: [("1 Handvoll", 30)], syn: ["Erdnuss", "Spanische Nüssli"])
        add("Erdnussbutter", nuts, 620, 25, 12, 50, sugar: 6, fiber: 6, salt: 0.6, servings: [("1 EL", 15)], syn: ["Erdnussmus", "Peanut Butter"])
        add("Chiasamen", nuts, 490, 17, 8, 31, sugar: 0, fiber: 34, salt: 0, servings: [("1 EL", 12)], syn: ["Chia"], ca: 630)
        add("Leinsamen", nuts, 530, 18, 2, 42, sugar: 1.5, fiber: 27, salt: 0.1, servings: [("1 EL", 10)], syn: ["Leinsaat"])
        add("Sonnenblumenkerne", nuts, 590, 21, 12, 51, sugar: 2.6, fiber: 9, salt: 0, servings: [("1 EL", 10)], syn: ["Kerne"])
        add("Kürbiskerne", nuts, 590, 30, 10, 49, sugar: 1.4, fiber: 6, salt: 0, servings: [("1 EL", 10)], syn: ["Kerne"], fe: 8.8, mg: 550)

        // MARK: Fette, Saucen & Würzmittel
        let fats = "Fette & Saucen"
        add("Olivenöl", fats, 884, 0, 0, 100, sugar: 0, fiber: 0, salt: 0, sat: 14, servings: [("1 EL", 10), ("1 TL", 4)], syn: ["Öl"])
        add("Rapsöl", fats, 884, 0, 0, 100, sugar: 0, fiber: 0, salt: 0, sat: 7, servings: [("1 EL", 10), ("1 TL", 4)], syn: ["Öl"])
        add("Margarine", fats, 720, 0.2, 0.4, 80, sugar: 0, fiber: 0, salt: 0.2, servings: [("1 Portion", 10)])
        add("Mayonnaise", fats, 700, 1, 1.5, 76, sugar: 1.3, fiber: 0, salt: 1.2, servings: [("1 EL", 15)], syn: ["Mayo"])
        add("Salatsauce French", fats, 380, 1, 5, 39, sugar: 3.5, fiber: 0, salt: 2, servings: [("1 EL", 15)], syn: ["Dressing", "Salatdressing"])
        add("Ketchup", fats, 110, 1.3, 25, 0.2, sugar: 22, fiber: 0.5, salt: 1.8, servings: [("1 EL", 15)], syn: ["Tomatenketchup"])
        add("Senf", fats, 90, 6, 5, 4.5, sugar: 3, fiber: 2, salt: 4, servings: [("1 TL", 5)], syn: ["Mostrich"])
        add("Pesto Genovese", fats, 450, 5, 6, 45, sugar: 3, fiber: 2, salt: 2.7, servings: [("1 EL", 15)], syn: ["Pesto", "Basilikumpesto"])
        add("Tomatensauce", fats, 50, 1.5, 7, 1.5, sugar: 5, fiber: 1.5, salt: 0.9, servings: [("1 Portion", 125)], syn: ["Sugo", "Pastasauce"])

        // MARK: Süsses & Snacks
        let sweets = "Süsses & Snacks"
        add("Milchschokolade", sweets, 545, 7, 56, 32, sugar: 54, fiber: 2, salt: 0.2, sat: 19, servings: [("1 Reihe", 25), ("1 Tafel", 100)], syn: ["Schokolade", "Schoggi"])
        add("Dunkle Schokolade 70 %", sweets, 580, 9, 34, 43, sugar: 28, fiber: 11, salt: 0.02, sat: 26, servings: [("1 Reihe", 25)], syn: ["Schokolade", "Zartbitter", "Schoggi"], fe: 11, mg: 230)
        add("Nuss-Nougat-Creme", sweets, 540, 6, 57, 31, sugar: 56, fiber: 3, salt: 0.1, servings: [("1 Portion", 15)], syn: ["Schokoaufstrich", "Brotaufstrich"])
        add("Konfitüre", sweets, 250, 0.4, 60, 0.1, sugar: 58, fiber: 1, salt: 0, servings: [("1 Portion", 20)], syn: ["Marmelade", "Konfi"])
        add("Honig", sweets, 305, 0.4, 76, 0, sugar: 76, fiber: 0, salt: 0, servings: [("1 TL", 8), ("1 EL", 20)])
        add("Zucker", sweets, 400, 0, 100, 0, sugar: 100, fiber: 0, salt: 0, servings: [("1 TL", 4), ("1 Würfel", 3)])
        add("Gummibärchen", sweets, 340, 7, 77, 0.2, sugar: 47, fiber: 0, salt: 0.05, servings: [("1 Portion", 25)], syn: ["Gummibärli", "Fruchtgummi"])
        add("Kartoffelchips", sweets, 540, 6, 50, 34, sugar: 0.5, fiber: 4.5, salt: 1.4, servings: [("1 Portion", 30)], syn: ["Chips", "Pommes Chips"])
        add("Salzstangen", sweets, 380, 10, 77, 3, sugar: 2, fiber: 3, salt: 4, servings: [("1 Portion", 30)], syn: ["Salzstängeli", "Brezeln"])
        add("Getreideriegel", sweets, 410, 7, 64, 13, sugar: 28, fiber: 5, salt: 0.3, servings: [("1 Riegel", 25)], syn: ["Müesliriegel", "Riegel"])
        add("Proteinriegel (Durchschnitt)", sweets, 360, 33, 30, 12, sugar: 4, fiber: 8, salt: 0.5, servings: [("1 Riegel", 55)], syn: ["Riegel", "Protein Bar"])
        add("Glace Vanille", sweets, 210, 3.5, 24, 11, sugar: 21, fiber: 0, salt: 0.1, servings: [("1 Kugel", 50)], syn: ["Glacé", "Eis", "Speiseeis", "Eiscreme"])
        add("Whey-Proteinpulver", sweets, 380, 78, 7, 5, sugar: 5, fiber: 0, salt: 0.4, servings: [("1 Portion", 30)], syn: ["Protein", "Proteinpulver", "Eiweisspulver", "Shake"])

        // MARK: Gerichte
        let dishes = "Gerichte"
        add("Käsefondue", dishes, 240, 15, 2.5, 18, sugar: 0.5, fiber: 0, salt: 1.3, servings: [("1 Portion", 200)], syn: ["Fondue", "Moitié-moitié"])
        add("Älplermagronen", dishes, 170, 6.5, 18, 8, sugar: 1.5, fiber: 1.2, salt: 0.8, servings: [("1 Portion", 350)], syn: ["Älplermakkaroni", "Magronen"])
        add("Pizza Margherita", dishes, 240, 10, 30, 8.5, sugar: 3, fiber: 2, salt: 1.3, servings: [("1 Pizza", 350), ("1 Stück", 90)], syn: ["Pizza"])
        add("Spaghetti Bolognese", dishes, 135, 6.5, 17, 4.5, sugar: 2.5, fiber: 1.5, salt: 0.6, servings: [("1 Teller", 400)], syn: ["Bolognese", "Pasta"])
        add("Lasagne", dishes, 150, 8, 13, 7, sugar: 2.5, fiber: 1, salt: 0.8, servings: [("1 Portion", 350)], syn: ["Lasagna"])
        add("Hamburger", dishes, 250, 13, 25, 11, sugar: 5, fiber: 1.5, salt: 1.2, servings: [("1 Stück", 200)], syn: ["Burger"])
        add("Döner Kebab", dishes, 215, 12, 21, 9, sugar: 2.5, fiber: 1.5, salt: 1.3, servings: [("1 Stück", 350)], syn: ["Kebab", "Döner"])
        add("Sushi Maki", dishes, 150, 4.5, 29, 1.5, sugar: 5, fiber: 1, salt: 1, servings: [("1 Stück", 25)], syn: ["Sushi", "Maki"])
        add("Gemischter Salat mit Sauce", dishes, 80, 1.5, 4, 6.5, sugar: 2.5, fiber: 1.5, salt: 0.6, servings: [("1 Teller", 200)], syn: ["Salat", "Beilagensalat"])

        // MARK: Getränke (pro 100 ml)
        let drinks = "Getränke"
        add("Wasser", drinks, 0, 0, 0, 0, sugar: 0, fiber: 0, salt: 0, liquid: true, servings: [("1 Glas", 250), ("1 Flasche", 500)], syn: ["Hahnenwasser", "Leitungswasser"])
        add("Mineralwasser", drinks, 0, 0, 0, 0, sugar: 0, fiber: 0, salt: 0, liquid: true, servings: [("1 Glas", 250), ("1 Flasche", 500)], syn: ["Wasser", "Sprudel"])
        add("Kaffee schwarz", drinks, 2, 0.1, 0, 0, sugar: 0, fiber: 0, salt: 0, liquid: true, servings: [("1 Tasse", 200)], syn: ["Kaffee", "Café crème", "Filterkaffee"], caffeine: 55)
        add("Espresso", drinks, 9, 0.1, 1.7, 0.2, sugar: 0, fiber: 0, salt: 0, liquid: true, servings: [("1 Tasse", 30)], syn: ["Kaffee", "Ristretto"], caffeine: 210)
        add("Cappuccino", drinks, 40, 2, 3, 2, sugar: 3, fiber: 0, salt: 0.05, liquid: true, servings: [("1 Tasse", 200)], syn: ["Kaffee", "Cappu"], caffeine: 35)
        add("Latte Macchiato", drinks, 45, 2.5, 3.5, 2.3, sugar: 3.5, fiber: 0, salt: 0.05, liquid: true, servings: [("1 Glas", 300)], syn: ["Milchkaffee", "Kaffee", "Latte"], caffeine: 25)
        add("Schwarztee", drinks, 1, 0, 0.2, 0, sugar: 0, fiber: 0, salt: 0, liquid: true, servings: [("1 Tasse", 250)], syn: ["Tee"], caffeine: 20)
        add("Kräutertee", drinks, 1, 0, 0.2, 0, sugar: 0, fiber: 0, salt: 0, liquid: true, servings: [("1 Tasse", 250)], syn: ["Tee", "Pfefferminztee", "Kamillentee"])
        add("Orangensaft", drinks, 45, 0.7, 9.5, 0.2, sugar: 9, fiber: 0.2, salt: 0, liquid: true, servings: [("1 Glas", 200)], syn: ["O-Saft", "Orangenjus", "Saft"], vitC: 40)
        add("Apfelsaft", drinks, 46, 0.1, 11, 0.1, sugar: 10, fiber: 0, salt: 0, liquid: true, servings: [("1 Glas", 200)], syn: ["Süssmost", "Saft"])
        add("Apfelschorle", drinks, 25, 0.1, 6, 0, sugar: 5.5, fiber: 0, salt: 0, liquid: true, servings: [("1 Glas", 300)], syn: ["Apfelschorle", "Gespritzter"])
        add("Cola", drinks, 42, 0, 10.6, 0, sugar: 10.6, fiber: 0, salt: 0, liquid: true, servings: [("1 Dose", 330), ("1 Flasche", 500)], syn: ["Softdrink"], caffeine: 10)
        add("Cola zuckerfrei", drinks, 0.3, 0, 0, 0, sugar: 0, fiber: 0, salt: 0.02, liquid: true, servings: [("1 Dose", 330), ("1 Flasche", 500)], syn: ["Cola light", "Zero", "Softdrink"], caffeine: 10)
        add("Eistee", drinks, 28, 0, 7, 0, sugar: 7, fiber: 0, salt: 0, liquid: true, servings: [("1 Glas", 300), ("1 Flasche", 500)], syn: ["Ice Tea"])
        add("Energy Drink", drinks, 45, 0, 11, 0, sugar: 11, fiber: 0, salt: 0.1, liquid: true, servings: [("1 Dose", 250)], syn: ["Energydrink"], caffeine: 32)
        add("Isotonisches Sportgetränk", drinks, 25, 0, 6, 0, sugar: 6, fiber: 0, salt: 0.1, liquid: true, servings: [("1 Flasche", 500)], syn: ["Sportgetränk", "Elektrolyt"])
        add("Smoothie", drinks, 55, 0.6, 12, 0.2, sugar: 11, fiber: 1.2, salt: 0, liquid: true, servings: [("1 Flasche", 250)], syn: ["Fruchtsmoothie"])
        add("Kakao mit Milch", drinks, 80, 3.3, 11, 2.5, sugar: 10, fiber: 0.5, salt: 0.1, liquid: true, servings: [("1 Tasse", 250)], syn: ["Schokoladenmilch", "Ovo", "Kakao"])
        add("Bier", drinks, 42, 0.4, 3, 0, sugar: 0.2, fiber: 0, salt: 0, liquid: true, servings: [("1 Stange (3 dl)", 300), ("1 Flasche (5 dl)", 500)], syn: ["Lager", "Helles", "Stange"])
        add("Bier alkoholfrei", drinks, 25, 0.3, 5, 0, sugar: 3, fiber: 0, salt: 0, liquid: true, servings: [("1 Flasche", 330)], syn: ["Bier"])
        add("Rotwein", drinks, 85, 0.1, 2.6, 0, sugar: 0.6, fiber: 0, salt: 0, liquid: true, servings: [("1 Glas (1.5 dl)", 150)], syn: ["Wein"])
        add("Weisswein", drinks, 82, 0.1, 2.6, 0, sugar: 1, fiber: 0, salt: 0, liquid: true, servings: [("1 Glas (1.5 dl)", 150)], syn: ["Wein", "Fendant", "Chasselas"])
        add("Prosecco", drinks, 75, 0.1, 1.5, 0, sugar: 1.5, fiber: 0, salt: 0, liquid: true, servings: [("1 Glas", 100)], syn: ["Schaumwein", "Sekt", "Cüpli"])

        return items
    }
}
