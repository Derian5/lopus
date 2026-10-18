class_name SoldierNameGenerator
extends RefCounted


# Hebrew, Yiddish, Biblical, and Old Slavic names in ASCII transliteration.
const NAMES: Array[String] = [
	"Aaron", "Abel", "Abigail", "Abner", "Abraham", "Ada", "Adah", "Adam", "Adina", "Akiva",
	"Aliza", "Amalia", "Amos", "Ari", "Ariel", "Asa", "Asher", "Atara", "Avigdor", "Avital",
	"Aviva", "Azariah", "Barak", "Baruch", "Batya", "Benjamin", "Boaz", "Caleb", "Carmi", "Chaim",
	"Chana", "Chava", "Dalia", "Daniel", "David", "Deborah", "Dinah", "Dov", "Efraim", "Ehud",
	"Eli", "Eliana", "Eliezer", "Elijah", "Elisheva", "Elkanah", "Esther", "Ezra", "Gabriel", "Gad",
	"Galit", "Gershon", "Gideon", "Gila", "Golda", "Hadar", "Hadassah", "Hagar", "Hanan", "Hannah",
	"Hava", "Hillel", "Hodaya", "Ilana", "Isaac", "Isaiah", "Israel", "Itamar", "Jacob", "Jael",
	"Jeremiah", "Jesse", "Joachim", "Joel", "Jonah", "Jonathan", "Joseph", "Joshua", "Judith", "Keren",
	"Leah", "Levi", "Liora", "Malachi", "Meir", "Menachem", "Micah", "Miriam", "Mordecai", "Moses",
	"Naama", "Naomi", "Nathan", "Nehemiah", "Netanel", "Noa", "Noah", "Oren", "Oz", "Penina",
	"Rachel", "Raphael", "Rebecca", "Reuben", "Rivka", "Ruth", "Samson", "Samuel", "Sarah", "Saul",
	"Shai", "Shalom", "Shimon", "Shira", "Shmuel", "Solomon", "Talia", "Tamar", "Tirzah", "Tobias",
	"Uri", "Uriel", "Yaakov", "Yair", "Yarden", "Yehuda", "Yonah", "Yosef", "Yotam", "Zechariah",
	"Ziva", "Zohar", "Zipporah", "Alter", "Anschel", "Berel", "Bluma", "Chaya", "Feivel", "Fruma",
	"Hershel", "Hinda", "Itzik", "Keila", "Kreina", "Lazer", "Mendel", "Moishe", "Nechama", "Peretz",
	"Bazhen", "Belogor", "Belomir", "Beloslav", "Berislav", "Blagomir", "Boleslav", "Bogdan", "Bogomil", "Boguslav",
	"Borimir", "Borislav", "Bozhidar", "Branibor", "Branimir", "Branislav", "Bratomir", "Bratislav", "Bretislav", "Bronislav",
	"Budimir", "Buyan", "Caslav", "Cedomir", "Dalibor", "Domaslav", "Dobrogost", "Dobromil", "Dobromir", "Dobroslav",
	"Dragomir", "Dragoslav", "Goran", "Gostomysl", "Gostislav", "Gradimir", "Hotimir", "Iziaslav", "Jaromir", "Jaropolk",
	"Jaroslav", "Kazimir", "Krasimir", "Ladomir", "Lubomir", "Luboslav", "Ludomir", "Mechislav", "Mieczyslaw", "Milan",
	"Milen", "Milogost", "Milomir", "Milorad", "Miloslav", "Milivoj", "Mojmir", "Mstislav", "Nemir", "Ognjen",
	"Predrag", "Pribislav", "Radogost", "Radomir", "Radoslav", "Ratislav", "Ratibor", "Ratimir", "Rogvolod", "Rostislav",
	"Stanislav", "Svetogor", "Svetomir", "Svetoslav", "Sviatopolk", "Sviatoslav", "Tihomir", "Tomislav", "Tverdislav", "Vadim",
	"Velibor", "Velimir", "Vladimir", "Vladislav", "Vojislav", "Volodar", "Vsevolod", "Vseslav", "Vyacheslav", "Yaropolk",
	"Zbigniew", "Zdeslav", "Zhivko", "Zoran", "Zvenimir", "Zlatan", "Zlatomir", "Zvonimir", "Bazhana", "Beloslava",
	"Berislava", "Blagovesta", "Bogdana", "Bogumila", "Boguslava", "Bojana", "Boleslava", "Borislava", "Bozena", "Branislava",
	"Bratislava", "Bronislava", "Cvetana", "Dobrava", "Dobromila", "Dobroslava", "Domaslava", "Dragana", "Dragomira", "Dragoslava",
	"Gordana", "Gostislava", "Jaromira", "Jaroslava", "Kazimira", "Krasimira", "Lada", "Ladislava", "Lubava", "Lubomira",
	"Luboslava", "Ludmila", "Malusha", "Milada", "Milana", "Milena", "Milica", "Miloslava", "Mira", "Miroslava",
	"Mstislava", "Nadezhda", "Nevena", "Ognjena", "Pribislava", "Rada", "Radmila", "Radomira", "Radoslava", "Ratislava",
]


static func assign_name(soldier: SoldierState, job_display_name: String, run_seed: int, roster: Array[SoldierState]) -> void:
	var used_names: Dictionary = {}
	for existing in roster:
		if not existing.personal_name.is_empty():
			used_names[existing.personal_name] = true
	var start_index := _seeded_index(run_seed, soldier.unique_id)
	for offset in NAMES.size():
		var candidate := NAMES[(start_index + offset) % NAMES.size()]
		if not used_names.has(candidate):
			soldier.personal_name = candidate
			soldier.generated_name = format_name(job_display_name, candidate)
			return
	# A run cannot normally hold this many soldiers, but keep generation total.
	soldier.personal_name = NAMES[start_index]
	soldier.generated_name = format_name(job_display_name, soldier.personal_name)


static func update_job_name(soldier: SoldierState, old_job_display_name: String, new_job_display_name: String) -> void:
	if soldier.personal_name.is_empty():
		var prefix := old_job_display_name + " "
		soldier.personal_name = soldier.generated_name.trim_prefix(prefix) if soldier.generated_name.begins_with(prefix) else soldier.generated_name
	if not soldier.personal_name.is_empty():
		soldier.generated_name = format_name(new_job_display_name, soldier.personal_name)


static func format_name(job_display_name: String, personal_name: String) -> String:
	return "%s %s" % [job_display_name, personal_name]


static func _seeded_index(run_seed: int, unique_id: String) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%s" % [run_seed, unique_id]).hash()
	return rng.randi_range(0, NAMES.size() - 1)
